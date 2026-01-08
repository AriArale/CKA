# Kubernetes CKA 學習筆記 Part17 - 2026 CKA 備考戰略與必背指令集 (Hardcore Cheat Sheet)

**目標:** 2026/01/30 一次通關 CKA  
**倒數:** 24 天  
**核心哲學:** 80% Imperative (指令生成), 20% Declarative (查表修 YAML)。速度即生存。  
**date:** 2026-01-07

---

## 1. 戰場生存配置 (Exam Environment Setup)
進入考試終端機的第一分鐘，**什麼題目都不要看**，先輸入這四行建立武器庫。

```bash
# 1. 設定縮寫 (考試環境通常預設有，但打一下確認心安)
alias k=kubectl

# 2. 設定 DRY-RUN 變數 (價值連城，節省 50% 打字時間)
export d="--dry-run=client -o yaml"
export ETCDCTL_API=3

# 3. 解決 YAML 縮排地獄 (Vim 優化)
# 讓貼上 YAML 時不會格式跑掉，這是 YAML 編輯的保命符
echo 'set autoindent' >> ~/.vimrc
# echo 'set expandtab' >> ~/.vimrc
# echo 'set shiftwidth=2' >> ~/.vimrc 

# 4. 測試與暖機
k run nginx --image=nginx $d  # 應立刻吐出 YAML
```

## 2. 肌肉記憶指令集 (Imperative Muscle Memory)

以下指令必須練到**反射動作**等級。能用指令解決的，絕對不要手寫 YAML。

### A. 基礎物件 (Workloads)

- **Pod:**

```bash
    k run my-pod --image=nginx --restart=Never $d
```

- **Deployment:**

```bash
    k create deploy my-dep --image=nginx --replicas=3 $d
```

- **DaemonSet (陷阱題):**
    
    - **沒有 `k create daemonset` 指令！**
        
    - **SRE 戰略:** 先生成 Deployment YAML，然後修改 `kind: Deployment` 為 `DaemonSet`，並刪除 `spec.replicas` 和 `spec.strategy` 欄位。
        
- **Scaling:**
	
```bash
    k scale deploy my-dep --replicas=5
```


### B. 網路暴露 (Service)

- **ClusterIP (預設 - 內部用):** 

```bash
    k expose deploy my-dep --port=80 --target-port=8080 --name=my-svc $d
```

- **NodePort (對外用):** 

```bash
    k expose deploy my-dep --port=80 --target-port=8080 --type=NodePort --name=my-svc $d
```
- **重點:** `targetPort` 必須等於 Container 內部的 Port。
 
- **除錯:** `k get ep <svc-name>` (檢查 Endpoints 是否有 IP)。

### C. 配置與權限 (Config & RBAC)

- **ConfigMap / Secret:**

```bash
    k create cm my-config --from-literal=APP_ENV=prod $d
    k create secret generic my-pass --from-literal=password=123456 $d
```

- **ServiceAccount:**

```bash
    k create sa my-sa $d
```

- **RBAC (大魔王 - 務必指令化):**
  
```bash
    # 1. 建立角色 (定義 Local 權限)
    k create role pod-reader --verb=get,list,watch --resource=pods $d
    
    # 2. 綁定角色 (綁給 SA)
    # 注意 serviceaccount 格式為 <namespace>:<name>
    k create rolebinding my-binding --role=pod-reader --serviceaccount=default:my-sa $d
```

- **權限驗證 (Can-I):**

```bash
    k auth can-i create deployments --as=system:serviceaccount:default:my-sa
```

### D. 排程 (CronJob)

- **CronJob:**

```bash
    k create cronjob my-job --image=busybox --schedule="*/1 * * * *" $d -- /bin/sh -c "date"
```

---

## 3. SRE 除錯與維護 (Troubleshooting & Maintenance) - 30% 重點

### A. 除錯神器 (Log & Events)

- **時間軸偵探 (必背):** 當發生一連串錯誤，想知道「誰先死」的時候。

```bash
    k get events -A --sort-by='{.metadata.creationTimestamp}'
```
    
- **Log 分析:**
    
    - **Pod:** `k logs <pod> -c <container>` (多容器必加 `-c`)。
        
    - **Node/Kubelet:** `journalctl -u kubelet | tail -n 20`。
        
    - **API Server:** `crictl ps | grep apiserver` -> `crictl logs <id>`。
        

### B. 網路連線測試 (Connectivity)

- **免洗筷 Pod (一次性 curl):** 當環境沒有工具時，用這招測連線。

```bash
    k run tmp-test --image=nginx:alpine --restart=Never --rm -i -- curl -m 2 <TARGET_IP>
```

### C. 叢集升級 (Cluster Upgrade) - 25% 重點

**背熟順序，不要跳步。**

1. **Plan:** `kubeadm upgrade plan`
    
2. **Drain:** `k drain <node> --ignore-daemonsets`
    
3. **Upgrade (Master):** `kubeadm upgrade apply v1.xx.x`
    
4. **Upgrade (Worker):** `kubeadm upgrade node`
    
5. **Restart:** `systemctl restart kubelet`
    
6. **Restore:** `k uncordon <node>`

### D. 備份與還原 (ETCD Backup)

- **指令:**

```bash
	ETCDCTL_API=3 etcdctl snapshot save <path> \ 
	--cacert=/etc/kubernetes/pki/etcd/ca.crt \ 
	--cert=/etc/kubernetes/pki/etcd/server.crt \ 
	--key=/etc/kubernetes/pki/etcd/server.key
```

- **關鍵參數:** 務必從 `cat /etc/kubernetes/manifests/etcd.yaml` 裡找這三個路徑：
    
    - `--trusted-ca-file=...` (對應指令的 `--cacert`)
		
    - `--cert-file=...` (對應指令的 `--cert`)
	    
    - `--key-file=...` (對應指令的 `--key`)

---

## 4. 關鍵 YAML 陷阱與查表指南

### A. Ingress (Services & Networking)

- **搜尋關鍵字:** `ingress`
    
- **必改重點:**
    
    - **Rewrite:** `metadata.annotations` 加上 `nginx.ingress.kubernetes.io/rewrite-target: /`
        
    - **ClassName:** `spec.ingressClassName: nginx` (一定要檢查環境是用哪個 class)。
        
    - **PathType:** 通常設為 `Prefix`。

### B. NetworkPolicy

- **搜尋關鍵字:** `network policy`
    
- **邏輯陷阱:**
    
    - **Default Deny:** `podSelector: {}` + `policyTypes: [Ingress]` (阻擋所有進入流量)。
        
    - **Namespace Selector:** 注意 YAML 裡不要寫死 `namespace: xxx`，改用 `k apply -f np.yaml -n <ns>` 帶入，避免衝突。

### C. PersistentVolume (Storage)

- **搜尋關鍵字:** `persistent volume`
    
- **手寫地獄:** 這題通常無法用指令生成，必須複製貼上。
    
- **重點:** 搞清楚 `hostPath` (Node 本地路徑) 與 `nfs` (網路硬碟) 的 YAML 寫法差異。

### D. Static Pod (Node Management)

- **特徵:** Pod 名稱後面有 `-<node-name>`，無法被 `kubectl delete`。
    
- **路徑:** 預設在 `/etc/kubernetes/manifests/`。
    
- **操作:** 只能透過 **SSH 到 Node 上**，移動/修改/刪除 YAML 檔案來控制。

---
## 5. 25 天倒數戰鬥計畫 (The Battle Plan)

**狀態:** 平日晚上 2hr (19:00-21:00)，週末全天。

### Phase 1: 肌肉記憶固化 (1/6 - 1/9)

- **目標:** 徹底拋棄手寫 YAML 習慣。
    
- **平日晚上:** Killercoda Playground。
    
    - 瘋狂練習 **Section 2** 的指令。
        
    - **特別特訓:** Deployment 轉 DaemonSet 的手速。
        
    - **特別特訓:** `k get events` 排序指令的背誦。

### Phase 2: 第一次模擬考 (1/10 週末)

- **工具:** **Killer.sh Simulator** (Session 1)。
    
- **週六 (1/10):**
    
    - **09:00 - 11:30:** 全真模擬考 (預期分數 < 50%，心態穩住)。
        
    - **13:30 - 18:00:** **逐題檢討**。不管對錯，每一題都看解答。
        
- **週日 (1/11):**
    
    - **09:00 - 11:00:** Reset Cluster，**重做同一份考卷**。
        
    - **目標:** 速度訓練。全對且 2 小時內做完。

### Phase 3: 針對性補強 (1/12 - 1/23)

- **平日晚上:** 針對 Phase 2 暴露的弱點 (例如 Storage 或 Upgrade) 進行專項練習。
    
- **工具:** Killercoda (特定 Scenario) 或 Chad M. Crowell 的練習題。    

### Phase 4: 終極演習 (1/24 週末)

- **工具:** **Killer.sh Simulator** (Session 2)。
    
- **週六 (1/24):** 再次全真模擬。
    
- **目標:** 像機器人一樣精準執行，分數 95% 以上。

### Phase 5: 考前封測 (1/25 - 1/29)

- 只複習這份筆記與錯題集。
    
- 早睡，保持腦袋清晰。

---

## 6. 考場 SRE 心法 (Mental Model)

1. **Context 切換:** 每一題開頭都有 `kubectl config use-context ...`，**一定要複製執行**，否則操作錯 Cluster 直接 0 分。
    
2. **Namespace 陷阱:** 題目若沒說 Default，務必加上 `-n <namespace>`。
    
3. **Flag & Skip:** 卡住超過 5 分鐘？**標記 Flag，直接下一題**。不要為了一棵樹放棄整片森林。
    
4. **結果論:** 只要 Pod 是 `Running` 且功能正常就好。YAML 排版醜沒關係，不要有潔癖。

祝武運昌隆。