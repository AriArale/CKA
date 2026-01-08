# Kubernetes CKA 學習筆記 Part10 - Affinity 驗證與工具的真實性

**重點:** `describe` 的顯示陷阱、YAML Source of Truth、**Affinity 動態驗證法 (移動靶心測試)**
**date:** 2025-12-17

---

## 1. 核心觀念：Describe vs YAML (工具信任論)

這是在 CKA 考試與除錯中最危險的誤區。

| 工具指令 | 性質 | 顯示內容 | SRE 判讀原則 |
| :--- | :--- | :--- | :--- |
| **`kubectl describe pod`** | **摘要 (Summary)** | 重點放在 Status、Events。**經常省略** Affinity、SecurityContext 等複雜巢狀結構。 | **僅供參考**。沒看到 Affinity 不代表沒設定成功。 |
| **`kubectl get pod -o yaml`** | **真理 (Source of Truth)** | 直接讀取 etcd 中的原始資料。包含所有 Spec 細節。 | **驗證設定是否寫入的唯一標準**。 |

**結論：** **使用 `-o yaml | grep affinity` 確認**。

---

## 2. Affinity 驗證神技：移動靶心測試 (Moving Target)

當環境節點很少，無法確定 Pod 是「隨機跑去那裡」還是「真的因為 Affinity 才去那裡」時，我們可以使用此測試法。

### 測試邏輯
Affinity 是「選室友」。如果我們強制把「室友 (Target Pod)」搬到別的房間，原本的 Pod 應該要跟著搬過去。

### 實戰步驟 (Scenario 復盤)

#### Step 1: 強制遷移目標 (The Magnet)

我們要先把目標 Pod (`restricted`) 搬到 `controlplane` 節點。
* **技巧：** 使用 **`nodeName: controlplane`**。
* **原理：** `nodeName` 會**繞過排程器 (Scheduler)**，無視 Taints，直接把 Pod 塞到該節點上。

```yaml
# restricted.yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted
  labels:
    level: restricted
spec:
  nodeName: controlplane  # <--- 強制指定位置
  containers:
  - image: nginx:alpine
    name: c
````

#### Step 2: 重建測試者 (The Follower)

刪除並重建設定了 Affinity 的 Pod (`hobby-project`)，觸發新的排程計算。

```bash
kubectl delete pod hobby-project --force --grace-period 0
kubectl apply -f hobby.yaml
```

#### Step 3: 驗證結果

檢查 `hobby-project` 是否真的跟著去了 `controlplane`。

```bash
kubectl get pod -o wide --show-labels
```

- **成功徵兆：** `hobby-project` 的 NODE 欄位顯示 `controlplane`。
- **原理：** 因為 `controlplane` 上面現在有 `level=restricted` 的 Pod，根據 Preferred Affinity 規則，該節點得分最高，所以 Scheduler 把 Pod 放在這裡。

---

## 3. 常用指令補充 (Force Replace)

在測試排程邏輯時，我們需要頻繁刪除重建 Pod。

- **快速刪除 (不等待)：**

```bash
kubectl delete pod <name> --force --grace-period 0
```

- **一鍵重建 (針對檔案)：**

```bash
kubectl replace --force -f <filename>.yaml
# 或者
kubectl delete -f <file> --force --grace-period 0 && kubectl apply -f <file>
```

---

## 4. 總結心得

1. **驗證設定：** 用 `kubectl get -o yaml` (不要只信 describe)。
2. **驗證邏輯：** 用 **「移動目標法」**。如果我把「吸鐵石 (Target Pod)」移走，「鐵釘 (Affinity Pod)」應該要跟著動。
3. **強制調度：** `spec.nodeName` 是測試時的好幫手，它可以無視規則直接指定節點。