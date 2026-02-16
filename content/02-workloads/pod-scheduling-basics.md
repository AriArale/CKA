# Kubernetes CKA 學習筆記 Part9 - 排程、親和性與除錯技巧

**重點:** Log 分析、Pod Preemption (搶佔)、Affinity 語法陷阱、TopologyKey 解析  
**date:** 2025-12-16

---

## 1. Linux Log 分析神技：`grep`

SRE 在除錯時，重點往往不是錯誤發生的「當下」，而是發生「之前」的徵兆。

### 指令詳解
```bash
grep -i priority -B 20 filename
````

- **`-i` (--ignore-case)**: **忽略大小寫**。確保 `Priority`, `priority`, `PRIORITY` 都能抓到。
- **`-B 20` (--before-context)**: **往前追溯 20 行**。
    - **用途：** 找出錯誤發生的 **前因 (Context)**。
    
- **比較：**
    - `-A <n>` (After): 往後看 n 行 (看 Stack Trace)。
    - `-C <n>` (Context): 上下都看。

---

## 2. Kubernetes 排程機制：搶佔 (Preemption)

當 Cluster 資源不足時，高優先級 (High Priority) 的 Pod 會踢掉低優先級的 Pod。

### Log 發生的時間軸 (由先到後)

1. **FailedScheduling**: 新 Pod 想進場，但 Node 記憶體不足。
2. **Preempted**: Scheduler 決定為了新 Pod，犧牲現有的低優先級 Pod。
3. **Killing**: Kubelet 執行處決，殺掉舊 Pod。
4. **Scheduled**: 資源釋出，新 Pod 成功排程。
5. **Started**: 新 Pod 啟動。

- **關鍵物件：** `PriorityClass` (定義優先級數值)。

---

## 3. 除錯加速器：Event 排序

`kubectl get events` 預設順序混亂，難以釐清因果關係。

### 必背指令

```bash
k get events -A --sort-by='{.metadata.creationTimestamp}'
```

- **`--sort-by`**: 指定排序欄位。
- **`{.metadata.creationTimestamp}`**: JSONPath 語法，依據事件建立時間由舊到新排序。
- **效益：** 將散亂的事件整理成連貫的「故事」，秒殺除錯時間。

---

## 4. Affinity (親和性) 核心觀念

### A. NodeAffinity vs PodAffinity

|**類型**|**譬喻**|**檢查對象**|**應用場景**|
|---|---|---|---|
|**NodeAffinity**|**選房子**|**Node** 的 Label|指定硬體 (SSD, GPU)、指定區域。|
|**PodAffinity**|**選室友**|**其他 Pod** 的 Label|前後端服務靠近 (低延遲)。|

### B. 語法陷阱 (Required vs Preferred)

- **Required (硬性):** 結構簡單，直接列條件。
- **Preferred (軟性):** 結構複雜，必須包含 **權重 (`weight`)** 與 **包裝層 (`preference`)**。
    - ❌ 錯誤：直接把 `labelSelector` 塞進列表。
    - ✅ 正確：
```yaml
    preferredDuringScheduling...:
        - weight: 100          # 必填
          preference:          # 必填包裝層 (舊版叫 podAffinityTerm)
            labelSelector: ...
```

### C. TopologyKey (定義「在一起」的範圍)

告訴 K8s 怎麼判斷兩個 Pod 是否算「在一起」。

- **`kubernetes.io/hostname`**: 範圍 = **同一台機器** (最嚴格)。
- **`topology.kubernetes.io/zone`**: 範圍 = **同一個機房/可用區** (較寬鬆，用於 HA)。

---

## 5. 安全性概念：Node Isolation

- **風險：** Kubelet 預設可以修改自己 Node 的 Label。
- **攻擊劇本：** 駭客攻破普通 Node → 修改 Label 偽裝成「機密 Node」(`role=secure`) → 騙取敏感 Pod 被調度過來 → 竊取資料。
- **防禦：** 使用 **NodeRestriction** Admission Plugin，禁止 Kubelet 修改敏感 Label。

---

## 6. CKA 考試必背指令集 (Cheatsheet)

### 快速生成 YAML (乾跑)

```bash
# 產生 Pod
k run nginx --image=nginx --restart=Never --dry-run=client -o yaml > pod.yaml

# 產生 Deployment
k create deploy my-dep --image=nginx --replicas=3 --dry-run=client -o yaml > deploy.yaml

# 產生 Service (這招最快，省去寫 Selector)
k expose deploy my-dep --port=80 --target-port=8080 --type=NodePort --dry-run=client -o yaml > svc.yaml
```

### 測試連線 (免洗筷 Pod)

```bash
# 臨時起一個 Pod 跑 curl，測完即刪
k run tmp-test --image=nginx:alpine --restart=Never --rm -i -- curl -m 5 <TARGET_IP>
```

### 權限驗證 (Auth Check)

```bash
# 檢查我可以做什麼
k auth can-i create pod

# 檢查 ServiceAccount (某個 Namespace 下的機器人) 可以做什麼
k auth can-i list secrets --as system:serviceaccount:<namespace>:<sa-name> -n <target-ns>
```

### 資訊檢索與排序

```bash
# 依時間排序事件 (除錯神器)
k get events -A --sort-by='{.metadata.creationTimestamp}'

# 顯示 Labels (檢查 Selector 對不對)
k get pod --show-labels
```