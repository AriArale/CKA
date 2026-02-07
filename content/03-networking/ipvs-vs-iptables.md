# Kubernetes CKA 學習筆記 Part24 - IPVS vs iptables

**重點:** IPVS hash table mechanism  
**date:** 2026-02-07

---
## 1. 核心邏輯：從「線性搜索」到「直接索引」
在網路層轉發中，效能瓶頸取決於「路由尋址」的演算法效率。

* **iptables (線性匹配機制)**
    * **邏輯**：類似在無目錄的書籍中尋找特定頁面，需由上而下逐條規則比對。
    * **複雜度**：$O(n)$。隨著規則數量增加，CPU 消耗呈線性增長。
* **IPVS (哈希表機制)**
    * **邏輯**：建立索引（Hash Table），透過 Key 直接映射記憶體位置。
    * **複雜度**：$O(1)$。無論規則數量多寡，尋址時間恆定。

---

## 2. IPVS vs. iptables 深度對比

| 特性 | iptables | IPVS (IP Virtual Server) |
| :--- | :--- | :--- |
| **底層資料結構** | 線性鏈表 (Linked List) | 哈希表 (Hash Table) |
| **搜尋效率** | 線性下降 $O(n)$ | 恆定高效 $O(1)$ |
| **更新機制** | **全量刷新**：修改一條規則需重載整張表 | **增量更新**：僅操作特定條目，原子性操作 |
| **負載演算法** | 簡單機率隨選 (Statistic/Random) | 專業調度演算法 (rr, lc, dh, sh, sed 等) |
| **核心依賴** | Netfilter 框架 | Netfilter 框架 + IPVS 核心模組 |

---

## 3. IPVS 的優勢與缺點 (Pros & Cons)

### 👍 優勢：為何成為大規模場景（如 K8s）的標準？

1.  **極致的擴展性**
    * 在 Kubernetes Service 數量突破 **1,000** 個後，IPVS 的轉發延遲保持平穩，而 iptables 延遲呈指數級上升。
2.  **CPU 消耗最佳化**
    * 繞過核心態的大量字串比對與規則掃描，將計算算力保留給業務邏輯。
3.  **更新無感（Atomic Updates）**
    * 在大規模 Pod 頻繁漂移（Deploy/Scale）時，IPVS 的增量更新機制避免了 iptables 因全量重載導致的網路抖動（Network Jitter）。
4.  **調度精準化**
    * 支援 `Least Connections` (lc) 等演算法，能感知後端真實負載，而非 iptables 的盲目輪詢。

### 👎 缺點與侷限性：代價分析

1.  **維運複雜度提升**
    * 需顯式載入核心模組（`ip_vs`, `ip_vs_rr`, `ip_vs_wrr`, `ip_vs_sh`），對 OS 依賴性較高。
2.  **除錯與可視化門檻**
    * iptables 可透過 `iptables -L` 直觀閱讀；IPVS 需使用 `ipvsadm`，且哈希表結構不具備直觀的邏輯順序。
3.  **功能邊界限制**
    * IPVS 是純粹的負載均衡器，不具備 iptables 的防火牆（Filter）、封包修改（Mangle）或日誌（Log）能力。
4.  **相容性陷阱**
    * 在舊版核心或特定 CNI（Container Network Interface）插件中，IPVS 可能與現有防火牆規則衝突，導致流量黑洞。

---

## 4. 量變產生質變的臨界點

根據 Kubernetes 社群壓測數據，切換 IPVS 的決策點通常位於：

* **Service 數量 > 1,000**：iptables 延遲開始顯著影響業務。
* **Pod 頻繁變動**：高頻部署導致 iptables 鎖競爭與 CPU 瞬間飆高（Spike）。
* **高併發長連接**：IPVS 的連接追蹤表（Connection Tracking）在大流量下優化優於標準 conntrack。

---

## 5. 總結筆記

* **iptables 是「萬能工具刀」**：
    * 功能全面（NAT、防火牆、LB），但缺乏專精，大規模作業時顯得笨重遲緩。
* **IPVS 是「專業手術刀」**：
    * 犧牲通用性與易用性，換取在極端規模下的絕對效能與低延遲。