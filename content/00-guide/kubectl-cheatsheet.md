# Kubernetes CKA 學習筆記 Part7 - kubectl exec 參數詳解

**重點:** kubectl exec 參數詳解  
**date:** 2025-12-13

---

```bash
K -n kube-system exec -it validate-checker-pod -- curl -m 1 app1.space1.svc.cluster.local

k -n default run nginx --image=nginx:1.21.5-alpine --restart=Never -i --rm -- curl -m 1 microservice1.space2.svc.cluster.local
```

這兩個指令雖然都是為了「測試連線」，但手段完全不同。

- **指令 1 (`exec`)**：是 **「寄生」** 在已經存在的 Pod 上面發動攻擊（測試）。
- **指令 2 (`run`)**：是 **「憑空創造」** 一個臨時的免洗 Pod 來發動攻擊，測完即丟。

以下是逐字逐參數的硬核拆解：

---

### 指令 1：寄生測試法

```bash
k -n kube-system exec -it validate-checker-pod -- curl -m 1 app1.space1.svc.cluster.local
```

這個指令的情境是：**「我要借用 `kube-system` namespace 裡的一顆現有 Pod，把它當作跳板來測試網路。」**

| 參數                         | 解釋                                                                                                       | SRE 觀點                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| **`k`**                    | `kubectl` 的縮寫 (Alias)。                                                                                   | 考試必設 alias，省時神器。                                                                 |
| **`-n kube-system`**       | **Namespace**。指定我們要操作的 Pod 位於 `kube-system` 這個房間裡。                                                       | 如果沒加，預設會去 `default` 找，找不到就會報錯。                                                   |
| **`exec`**                 | **Execute**。指令：「我要在容器內執行命令」。                                                                             | 這是進入**正在運行中**的 Pod 的標準方式。                                                        |
| **`-it`**                  | **Interactive + TTY**。<br><br>  <br><br>`-i`: 保持 Stdin (標準輸入) 開啟。<br><br>  <br><br>`-t`: 分配一個偽終端機 (TTY)。 | 雖然單純跑 `curl` 其實不需要 `-t`，但 `-it` 是肌肉記憶，習慣一起打，讓你能看到即時回饋。                           |
| **`validate-checker-pod`** | **Pod Name**。你要「寄生」的那顆 Pod 的名字。                                                                          | 這裡假設這顆 Pod 裡面已經裝有 `curl` 工具。如果它裡面沒裝 curl，指令會失敗。                                  |
| **`--`**                   | **分隔線 (Separator)**。左邊是 kubectl 的參數，右邊是容器內的指令。                                                           | **非常重要！** 告訴 K8s：「這裡之後的內容我不解析了，原封不動傳進容器裡執行。」                                     |
| **`curl`**                 | **Command**。在容器內執行的網路工具。                                                                                 | 用來發送 HTTP 請求。                                                                    |
| **`-m 1`**                 | **Max-time 1s**。設定 1 秒逾時。                                                                                | **NetworkPolicy 測試關鍵**。如果被防火牆擋掉 (Drop)，curl 預設會卡很久。設 1 秒讓它快速失敗 (Fail Fast)，節省時間。 |
| **`app1...local`**         | **Target URL**。目標服務的完整網域名稱 (FQDN)。                                                                       | 跨 Namespace 呼叫時的標準寫法。                                                            |

匯出到試算表

---

### 指令 2：免洗筷測試法 (臨時 Pod)

```bash
k -n default run nginx --image=nginx:1.21.5-alpine --restart=Never -i --rm -- curl -m 1 microservice1.space2.svc.cluster.local
```

這個指令的情境是：**「我現在手邊沒有好用的 Pod (或者我想模擬一個乾淨的環境)，請幫我馬上生一個，測完馬上幫我丟掉。」**

|參數|解釋|SRE 觀點|
|---|---|---|
|**`run nginx`**|**Run**。指令：「建立一個新的 Pod」，名字叫 `nginx`。|這是 Imperative (指令式) 建立 Pod 的最快方法。|
|**`--image=...alpine`**|**Image**。指定使用這個映像檔。|選 `alpine` 版本是因為它**體積小**且**內建 curl** (或 wget)，非常適合拿來當測試工具人。|
|**`--restart=Never`**|**Restart Policy**。設定為「永不重啟」。|**關鍵！** 預設是 `Always`。但這是一個「一次性任務」，跑完 curl 就該結束了，不需要它死掉又復活。|
|**`-i`**|**Interactive**。保持輸入通道開啟。|為了讓我們在終端機上能看到 curl 回傳的結果 (Output)。|
|**`--rm`**|**Remove**。任務結束後，自動刪除這個 Pod。|**SRE 必用參數**。保持叢集乾淨，不要留下一堆 `Completed` 狀態的垃圾 Pod。這就是「免洗筷」的精髓。|
|**`--`**|**分隔線**。同上。|分隔 K8s 設定與容器指令。|
|**`curl ...`**|**Command**。|這裡稍微有點不同：我們是在**覆蓋 (Override)** 容器預設的啟動指令 (原本 nginx image 預設是啟動 web server，這裡我們強迫它改跑 curl)。|

---

### 💡 總結與比較

- **什麼時候用指令 1 (`exec`)？**
    
    - 當你已經有一個好用的 Pod (例如 debug tools pod)。
    - 當你想模擬「從**特定 Pod** 出發」的流量 (例如測試 A 服務能不能連到 B 服務)。

- **什麼時候用指令 2 (`run --rm`)？**
    
    - 當該 Namespace 裡面沒有任何 Pod，或者現有的 Pod 裡面沒有裝 `curl`。
    - 當你想模擬「從**任意外部來源**」或「全新環境」連線的流量。
    - **CKA 考試技巧：** 如果題目要你驗證連線，但沒給你工具 Pod，就用這招快速生一個出來測，測完不留痕跡。