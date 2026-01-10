# Kubernetes CKA 學習筆記 Part21 - Resources, Labels & Admission Control

**重點:** Allocation vs Usage, Label Selectors, System Labels, Namespace Injections, Service Mesh Concepts  
**date:** 2026-01-10

---

## 1. 資源管理 (Resource Management)

### 預留 vs 使用 (Allocation vs. Usage)
* **Kubernetes 調度依據:** Scheduler 進行節點分配時，只看 **Requests (預留量)**，不看當下的實際 Usage (使用量)。
* **無 Metrics Server 時的檢查法:**
    * 指令: `kubectl describe node <node-name>` -> 查看 **Allocated resources** 區塊。
    * **意義:** 即便 Node CPU 使用率為 0%，如果所有 Pod 的 Requests 總和已達上限，Scheduler 仍會判定該節點額滿，導致新 Pod 處於 Pending 狀態。

### Metrics Server
* CKA 考場環境預設已安裝。
* **用途:** 提供 `kubectl top node` 與 `kubectl top pod` 指令所需的數據。
* **機制:** Metrics Server 會依賴 API Server 建立反向連線至 Kubelet (Summary API) 採集數據。

---

## 2. 標籤機制詳解 (Labels Deep Dive)

### 標籤的物理定義 (Physical Definition)
* **結構:** `key=value` 的鍵值對。
* **限制:** Value 為任意字串（最多 63 字元）；Key 可以是單純名稱（如 `app`）或包含前綴（如 `kubernetes.io/metadata.name`）。
* **通用性:** 幾乎所有 K8s 資源（Node, Pod, Namespace, Service, ConfigMap 等）皆可貼標籤。Metadata 中的 `labels` 欄位就像便利貼，用於分類與索引。

### "app" 標籤的本質 (The "app" Convention)
* **常見誤區:** `app` 這個 Key 在 Kubernetes 程式碼中**沒有任何特殊地位**。它純粹是一個字串，改成 `project=tester` 或 `service-name=tester` 系統一樣能運作。
* **多樣性原因:** 這是「人為約定」的結果。
    * **標準化:** Google 官方建議使用 `app.kubernetes.io/name`。
    * **習慣用法:** 傳統習慣使用簡潔的 `app`。
    * **系統組件:** Kube-system 常見 `k8s-app`。
    * **工具生成:** Helm Chart 會加上 `helm.sh/chart`。
* **實務建議:** 團隊內部應強制規範標籤標準（如統一要求 `app` 與 `env`），避免管理混亂。

---

## 3. 標籤類型考古學 (Label Taxonomy)

根據用途與來源，標籤可分為以下三類：

### A. 自動化系統標籤 (System Generated)
由 Controller 自動生成，通常不應手動修改。
* **`kubernetes.io/metadata.name=default` (Namespace):**
    * **功能:** 自 K8s 1.21 起自動加入。
    * **用途:** 讓 NetworkPolicy 可透過 `namespaceSelector` 直接選取特定名稱的 Namespace (無需手動標記)。
* **`pod-template-hash` (Deployment/ReplicaSet):**
    * **用途:** Deployment 識別 Pod 版本歸屬的依據。當 Image 更新，Hash 改變，Deployment 據此執行滾動更新 (Rolling Update)。
* **`controller-revision-hash` (StatefulSet):**
    * **用途:** 追蹤 StatefulSet 的版本歷史。
* **`statefulset.kubernetes.io/pod-name` (StatefulSet):**
    * **用途:** 配合 Headless Service，讓 DNS 能精確解析到特定的 Pod (如 `tester-0`)。

### B. 核心分類標籤 (Architecture Identity)
常見於 Control Plane 或靜態 Pod。
* **`component=kube-apiserver` / `tier=control-plane`:** 方便監控系統篩選核心組件。
* **`k8s-app=kube-dns`:** 標示為 K8s 內建應用程式。

### C. 服務綁定標籤 (Service Discovery Glue)
YAML 定義中最關鍵的部分，負責連結 Service 與 Pod。
* **機制:** Service 定義檔中的 `selector` 必須完全匹配 Pod 的 `labels`。
    ```yaml
    selector:
      app: tester  # 這裡必須完全匹配 Pod 的標籤
    ```
* **運作原理:** Service 持續掃描 Cluster，將流量導向所有匹配標籤的 Pod。若修改 Pod 標籤導致不匹配，Service 會立即斷開連結。

### 標籤用途總表
| 標籤範例 | 真正用途 (給誰看？) |
| :--- | :--- |
| `app=tester` | **Service** 用來決定導流目標。 |
| `tier=frontend` | **NetworkPolicy** 用來定義防火牆規則 (如「只有 backend 可連入」)。 |
| `env=production` | **CI/CD** 用來識別環境等級。 |
| `pod-template-hash=xyz` | **ReplicaSet** 用來識別所屬的 Pod 副本。 |

* **思考引導:** 看到 `labels` 時，應思考「這個標籤是為了讓哪個 Controller 或 Service 選中它？」。移除標籤通常會導致特定功能失效（如 Service 找不到 Endpoints）。

---

## 4. Namespace 進階應用與自動化控制

Namespace 的標籤常作為 **Admission Controller** 的「觸發開關」。可透過 `kubectl get ns --show-labels` 檢查。

### 常見觸發場景
1.  **Sidecar Injection (Service Mesh):**
    * 標籤: `istio-injection=enabled`
    * 行為: 觸發 Mutating Webhook，在 Pod 建立時自動注入 Sidecar Container (如 Envoy Proxy)。
2.  **Pod Security Admission (PSA):**
    * 標籤: `pod-security.kubernetes.io/enforce=restricted`
    * 行為: 強制阻擋不符合安全規範的 Pod (如特權容器)。
3.  **Network Policy:**
    * 行為: 作為 `namespaceSelector` 的篩選依據，控制跨 Namespace 的流量。

### 相關概念：Service Mesh / Sidecar
* **Sidecar Pattern:** 將網路通訊、加密、監控等功能從 App Container 剝離，交由同一 Pod 內的 Proxy Container 處理 (共享 Network Namespace)。
* **Service Mesh:** 由大量 Sidecar 構成的網格層，提供統一的可觀測性與流量控制。
* **代表工具:** Istio (基於 Envoy), Linkerd。