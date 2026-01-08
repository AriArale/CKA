# Kubernetes CKA 學習筆記 Part4 - Service 機制、除錯與 Ingress

**重點:** Service Port 隔離、Endpoints 除錯、Ingress 配置與未來趨勢
**date:** 2025-12-08

---

## 1. Service 的隔離性：為什麼 Port 80 不會衝突？

當我們執行以下指令時：
```bash
k -n world expose deploy europe --port 80
k -n world expose deploy asia --port 80
```
**結論：** 這**不會**導致衝突，兩者可以和平共存。

### 原因解析

1. **獨立 IP (ClusterIP)：** 每個 Service 建立時，K8s 會分配一個獨一無二的虛擬 IP。
    - Europe Service: `10.96.1.5:80`
    - Asia Service: `10.96.2.10:80`
    - **比喻：** 就像兩棟不同的房子（不同 IP），雖然都有一個大門（Port 80），但地址不同，郵差不會送錯。
    
2. **名稱不同：** `expose` 預設使用 Deployment 名稱作為 Service 名稱。只要 Service Name 不重複，etcd 就能區分。

**會衝突的情況：**
- **搶名字：** 指定完全相同的 `--name`。
- **搶 NodePort：** 兩個 Service 指定了同一個 **NodePort** (例如都硬要 `30001`)。

---

## 2. Port 的哲學：介面 vs 實作

釐清 `port` 與 `targetPort` 的 SRE 定義：

|**欄位**|**性質**|**SRE 定義 (解耦觀念)**|
|---|---|---|
|**Service Port (`port`)**|**介面 (Interface)**|**虛擬的**。K8s 內部的統一入口。外部程式呼叫此服務時，只需知道這個 Port (例如 80)，不用管後端改什麼。|
|**Target Port (`targetPort`)**|**實作 (Implementation)**|**真實的**。Container 內部程式實際監聽的 Port (例如 8080)。|

- **優勢：** 當容器內部的應用程式修改 Port (80 -> 8080) 時，只需修改 Service 的 mapping，不用通知所有呼叫端修改程式碼。

---

## 3. 關鍵除錯指令：`kubectl get ep`

當 Service 不通時，這是最重要的檢查指令。

- **指令：** `kubectl get ep` (列出 Endpoints)
- **意義：** 查看 Service 的「員工通訊錄」。Service 是一個虛擬總機，Endpoints 紀錄了它要把電話轉給哪些 **真實的 Pod IP**。    

### 除錯判讀

- **正常：** `ENDPOINTS` 欄位有 IP (如 `10.244.1.5:8080`)。
- **異常：** `ENDPOINTS` 顯示 `<none>`。
    - **可能原因 1：** **Selector 寫錯** (Service 找不到貼有對應 Label 的 Pod)。
    - **可能原因 2：** **Pod 全掛了** (沒有 Ready 的 Pod 可以接流量)。

---

## 4. 指令誤區：`kubectl get all`

- **觀念：** `get all` 只是一個 **「常用工作負載懶人包」**，並非真的列出叢集內的所有資源。
- **會列出：** Pod, Service, Deployment, ReplicaSet, StatefulSet, Job (會動的東西)。
- **看不到：**
    - **設定檔：** ConfigMap, Secret
    - **存儲：** PVC, PV
    - **網路規則：** Ingress
    - **權限：** ServiceAccount, RoleBinding

- **SRE 警示：** 千萬不要以為 `delete all` 就能把 Namespace 清乾淨，通常會留下設定檔和髒資料 (PVC)。    

---

## 5. Ingress vs Gateway API

雖然官方建議未來使用 Gateway API，但在 CKA 考試與現行維運中，Ingress 依然不可或缺。

- **Ingress (v1)：**
    - **CKA 考試：** **必考 (100% 權重)**。
    - **現狀：** 成熟穩定，簡單 HTTP 路由的首選，無需額外安裝 CRD。
    
- **Gateway API：**
    - **CKA 考試：** 目前非核心考題 (權重低，懂概念即可)。
    - **未來：** 解決 Ingress 的痛點 (如 TCP 路由、跨 Namespace)，但結構複雜。

- **結論：** 為了 2026 的考試，**請務必精通 Ingress YAML 的寫法**。

---

## 6. Ingress Backend 設定規則

### 官方文件的 "Mutually Exclusive" (互斥)

- **意思：** 在同一個 `backend` 區塊內，`service` 和 `resource` **只能二選一**。
- **錯誤寫法：**
 ```yaml
     backend:
      service: ...
      resource: ...  # ❌ 衝突！不能同時存在
```

### Killercoda 練習場景

- **題目：** "Two routes pointing to existing Services."
- **解析：** 這是要求建立 **兩個不同的 `path`**，分別指向不同的 Service。
- **正確寫法 (無衝突)：**
```yaml
    paths:
    - path: /app1
      backend:
        service: ... # ✅ 路徑 1 用 Service
    - path: /app2
      backend:
        service: ... # ✅ 路徑 2 也用 Service
    ```
- **Resource Backend 用途：** 連接靜態資源 (如 S3 Bucket)，考試極少用到。

