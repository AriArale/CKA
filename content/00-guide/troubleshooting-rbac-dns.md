# Kubernetes CKA 學習筆記 Part20 - Troubleshooting, RBAC & DNS

**重點:** Debugging Data Flow, Events Analysis, RBAC Verification, Service Discovery Formula  
**date:** 2026-01-10

---

## 1. 狀態查詢與除錯 (Get vs Describe)

### 資料流差異
| 指令 | 資料來源 | 查詢行為 | 用途 |
| :--- | :--- | :--- | :--- |
| `kubectl get pod` | **etcd** | 單次 API 呼叫 | 確認 Status, IP, Node 分配 (自動化/腳本用) |
| `kubectl describe pod` | **etcd** (多次) | 聚合查詢 (Pod + Events + Controllers) | **除錯診斷**。重點在於 **Events** 區塊 |

* **關鍵觀念:** `describe` 看到的 Events 是從 etcd 撈出來的歷史紀錄，**並非**即時去問 Kubelet。若 Kubelet 掛了，Events 依然存在。

### 除錯 SOP
1.  `get pod -o wide` (查看 Status 與 Node)。
2.  `describe pod` (查看 Events 原因，如 Scheduling Failed, ImagePullBackOff)。
3.  `logs` (查看 Application 內部噴錯，需連線至 Node)。

---

## 2. RBAC 權限排查

### 排查三部曲
1.  **聽診器:** `kubectl auth can-i <verb> <resource> --as <user> -n <namespace>`。
    * **務必檢查:** Namespace 的單複數拼字 (e.g., `application` vs `applications`)。
2.  **檢視報錯 (403 Forbidden):** 訊息會明確指出 User、Missing Verb、Resource 與 Namespace。
3.  **檢查 Binding:**
    * `RoleBinding` 與 `Role` 必須在**同一個 Namespace**。
    * 確認 `Subject` 的 `kind` (User vs ServiceAccount) 與 `name` 是否正確。

---

## 3. 服務發現 (DNS & Connectivity)

### DNS 黃金公式
Cluster 內完整網域名稱 (FQDN):
```text
<Service名稱>.<Namespace>.svc.cluster.local
```
- 跨 NS 呼叫: http://tester.level-1000.svc.cluster.local:8080

- 同 NS 簡寫: http://tester:8080

- 注意: DNS 只解析 IP，不包含 Port。Port 需查詢 Service 定義 (kubectl get svc)。