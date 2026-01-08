# Kubernetes 硬核觀念補充

**重點:** 網路分層模型、資料序列化原理、ConfigMap/Secret 機制、Workload 調度哲學
**date:** 2026-01-06

---

## 1. 網路架構：平行宇宙論 (Network Model)

**核心觀念：** Node Network 與 Pod Network 是兩個獨立的世界，透過 NAT 與 CNI 橋接。

| 層級 | IP 範例 | 來源 | 誰看得到？ | 說明 |
| :--- | :--- | :--- | :--- | :--- |
| **1. Node Network** | `192.168.1.5` | 實體路由器 / VPC | **外部世界** | 真實存在的網路層，**NodePort** 開在這裡。 |
| **2. Pod Network** | `10.244.1.3` | CNI 插件 | Cluster 內部 Pod | Overlay 虛擬內網，由 CNI 切割網段給各 Node。 |
| **3. Service Network** | `10.96.0.10` | Kube-apiserver | Cluster 內部 | **完全虛擬** (無網卡)，僅存在於 iptables/IPVS 規則中。 |

### Service Port 三兄弟 (流量路徑)
**路徑：** User $\to$ `NodeIP:nodePort` $\to$ (NAT) $\to$ `ServiceIP:port` $\to$ (LoadBalance) $\to$ `PodIP:targetPort`

* **`nodePort` (警衛室):** 開在 Node 上，給外部連。
* **`port` (總機):** 開在 Service 上，給內部連。
* **`targetPort` (分機):** **必須嚴格等於 Container 實際 Listen 的 Port**。

---

## 2. 資料結構：序列化與投影 (Serialization & Projection)

**核心觀念：** Etcd 存的是「資料 (Binary)」，Pod 看到的是「檔案 (Text)」，Kubelet 是中間的「渲染引擎」。

### 資料的旅程
1.  **YAML/JSON (Text):** 人類撰寫設定檔。
2.  **Protobuf (Binary):** API Server 將其**序列化**，存入 Etcd。
    * **目的：** 極致的儲存與傳輸效率 (比 JSON 快且小)。
    * **現象：** 直接看 `/var/lib/etcd` 裡的檔案是亂碼 (BoltDB 格式)。
3.  **File (Text):** Kubelet 讀取資料後，**反序列化**並透過 **Volume Projection** 寫入 Pod 的檔案系統。

### ConfigMap vs Secret
* **本質相同：** 都是 Key-Value 資料物件。
* **掛載行為：**
    * **Volume Mount:** 支援 **熱更新 (Hot Reload)** (除了 `subPath` 模式)。
    * **Env Var:** **不支援**熱更新 (需重啟 Pod)。
* **Secret 差異：**
    * 資料經過 Base64 編碼。
    * 掛載時寫入 **tmpfs (記憶體)**，不落地硬碟 (資安考量)。

---

## 3. Workload 調度哲學 (Scheduling Philosophy)

**核心觀念：** 根據「要數量」還是「要覆蓋率」選擇控制器。

| 特性 | Deployment | DaemonSet |
| :--- | :--- | :--- |
| **核心邏輯** | **填空題 (Replica-based)** | **連連看 (Node-based)** |
| **關注點** | 湊滿 `replicas` 數量 | 確保每個 Node 都有一個 |
| **Node 掛掉時** | **Reschedule:** 去別台 Node 重生 | **Die:** 跟著 Node 一起消失 |
| **典型應用** | Nginx, API, Redis | CNI, Kube-Proxy, Log Agent |

---

## 4. 靜態 Pod (Static Pods)

**核心觀念：** 解決「雞生蛋」問題的啟動機制。

* **定義：** 不受 API Server 管轄，由 **Kubelet** 直接讀取本地檔案啟動的 Pod。
* **特徵：**
    * Pod 名稱後綴帶有 `-<node-name>`。
    * `OwnerReference` 是 `Node`。
    * 本體檔案位於 `/etc/kubernetes/manifests/`。
* **成員：** `etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`。
* **Mirror Pod:** API Server 為了讓你知道它們存在，會建立一個唯讀的鏡像物件。

---

## 5. Etcd 操作與憑證 (Etcd Operations)

**核心觀念：** Etcd 是雙向認證 (mTLS) 的資料庫，操作必須帶「身分證」。

* **API 版本：** 務必設定 `ETCDCTL_API=3`，否則會連到 v2 空資料區。
* **備份指令 (Snapshot Save):**
    ```bash
    ETCDCTL_API=3 etcdctl snapshot save /tmp/backup.db \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key
    ```
* **路徑記憶法：** 不要死背路徑，去查看 `/etc/kubernetes/manifests/etcd.yaml` 裡的 Command 參數。

---

## 6. 電腦科學基礎 (CS Fundamentals)

* **Von Neumann vs Harvard:**
    * 現代電腦**宏觀**上是馮·紐曼架構 (RAM 內 Code/Data 混居)。
    * **微觀**上 (CPU 內部) 是哈佛架構 (L1 Cache 分離 Code/Data) 以提升效能。

- 1. 宏觀視角：RAM 是個大倉庫 (Von Neumann)  
	在您的 16GB 記憶體條 (RAM) 裡，**Data (資料)** 和 **Code (程式碼)** 是住在同一個物理空間的。
	
	- **Code (程式碼):** 這是應用程式的「指令本身」（例如 Chrome 瀏覽器的 `.app` 執行檔）。這通常佔比較小，幾百 MB 就算很大了。
	- **Data (資料):** 這是程式執行時產生的「內容」（例如 Chrome 開了 100 個分頁，每個分頁裡的圖片、文字、影片緩衝）。**這才是吃掉您 RAM 的元兇**。    

- 2. 微觀視角：CPU 內部的分流 (Harvard)
	那「Code 和 Data 分離」發生在哪？
	它發生在 資料從 RAM 被搬進 CPU 核心的那一瞬間。
	
	    a. **在 RAM 裡：** 大家混在一起（Von Neumann）。  
	    b. **在傳輸匯流排 (Bus) 上：** 排隊進 CPU。  
	    c. **進入 CPU L1 Cache：**  
	    警衛 (CPU Fetch Unit) 看到這是「指令 (`ADD`, `JMP`)」，把它踢進 **L1i (Instruction Cache)**。  
	    警衛看到這是「數值 (`User ID`, `Image Pixel`)」，把它踢進 **L1d (Data Cache)**。

- 3. 記憶體裡的 Data 結構 (Process Memory Layout)
	為了更具體理解 Data 怎麼佔用 RAM，一個執行中的程式 (Process) 在 RAM 裡通常切成這四塊：

| **區域**           | **內容 (Code vs Data)** | **佔用 RAM 行為**                                                       |
| ---------------- | --------------------- | ------------------------------------------------------------------- |
| **Text Segment** | **Code** (指令)         | **固定大小**。程式啟動後就不太會變大。                                               |
| **Data Segment** | **Data** (全域變數)       | **固定大小**。存一些設定值。                                                    |
| **Heap (堆積)**    | **Data** (動態物件)       | **無限膨脹**。您開越多分頁、修越多圖，這塊就會一直往上吃 RAM。**OOM (Out of Memory) 通常發生在這裡**。 |
| **Stack (堆疊)**   | **Data** (函式呼叫)       | **動態伸縮**。紀錄函式執行順序，佔用較少。                                             |
