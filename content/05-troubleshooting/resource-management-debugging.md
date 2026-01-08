# Kubernetes CKA 學習筆記 Part2 - 資源管理與除錯

**主題:** 宣告式管理、ConfigMap 掛載驗證、YAML 生成與排錯
**date:** 2025-12-04

---
## 1. 資源管理：Apply vs Create

這是 SRE 與 CKA 考試中必須區分的核心觀念。

| 指令 | 模式 | 行為 (資源不存在時) | 行為 (資源已存在時) | 適用場景 |
| :--- | :--- | :--- | :--- | :--- |
| **`kubectl create`** | **指令式 (Imperative)** | ✅ 建立成功 | ❌ **報錯** (`AlreadyExists`) | 快速產生一次性資源、考試時配合 `--dry-run` 使用。 |
| **`kubectl apply`** | **宣告式 (Declarative)** | ✅ 建立成功 | ✅ **更新狀態** (Configured) | **CI/CD 標準做法**、修改現有設定檔、版本控制。 |

* **SRE 觀念：** `apply` 具備 **冪等性 (Idempotency)**，不管執行幾次，結果都會確保與 YAML 描述的一致，是維運的首選。

---

## 2. ConfigMap 掛載驗證

當我們把 ConfigMap 掛載進 Pod 後，如何確認它真的生效？

### 驗證步驟
1.  **檢查源頭：** `k describe cm <name>` 確認 Key-Value 是否正確。
2.  **檢查結果：** `k exec <pod> -- ls -al /etc/<path>` 進入容器查看。

### 運作原理
Kubernetes 會將 ConfigMap 的 **Key 轉換為「檔名」**，**Value 轉換為「檔案內容」**。

* **原子更新 (Atomic Update) 機制：**
    * 觀察 `ls -al` 會發現檔案其實是 **Symbolic Link (軟連結)**。
    * 路徑指向 `..data`，而 `..data` 指向一個帶有時間戳記的資料夾。
    * **目的：** 當 ConfigMap 更新時，K8s 修改軟連結指向，達成瞬間切換內容，避免程式讀到寫入一半的損毀檔案。

---

## 3. CKA 神器：YAML 生成術

考試或工作中，為了避免手寫 YAML 發生語法錯誤，應使用「乾跑」指令生成模板。

### 指令
```bash
# 基本語法
--dry-run=client -o yaml

# 建議設定 Alias (加速用)
export do="--dry-run=client -o yaml"

# 範例：生成一個 Deployment YAML 到檔案中
k create deploy my-dep --image=nginx --replicas=3 $do > deploy.yaml
```

- **`--dry-run=client`**: 告訴 K8s 不要真的建立資源，只做語法檢查。
- **`-o yaml`**: 將預計產生的物件內容以 YAML 格式印出。

---

## 4. YAML 結構除錯 (Troubleshooting)

今天遇到的兩個經典錯誤，分別對應到「定義遺失」與「縮排錯誤」。

### 錯誤一：有借無還 (Mount without Definition)

- **錯誤訊息:** `The Pod "xxx" is invalid: spec.containers[0].volumeMounts[0].name: Not found: "birke"`
- **原因:** 在 Container 裡寫了 `volumeMounts` (插座)，但在 Pod 層級忘了寫 `volumes` (插頭)。
- **解法:** 補上 `volumes` 區塊。

### 錯誤二：層級錯亂 (Indentation Error)

- **錯誤訊息:** `strict decoding error: unknown field "spec.containers[0].volumes"`
- **原因:** 把 `volumes` 縮排寫在 `containers` 裡面（變成了容器的屬性）。
- **觀念:** **Volumes 屬於 Pod (共享資源)，不屬於單一 Container。**
- **解法:** 將 `volumes` 向左縮排，使其與 `containers` 對齊（平起平坐）。

### 正確結構範例

```yaml
spec:
  containers:      # [層級 1] 容器定義
  - name: my-app
    volumeMounts:  # [層級 2] 容器內掛載點
    - name: data
      mountPath: /data
  
  volumes:         # [層級 1] 必須跟 containers 對齊！
  - name: data
    configMap:
      name: my-config
```
