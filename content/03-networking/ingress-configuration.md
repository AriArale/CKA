# Kubernetes CKA 學習筆記 Part5 - Ingress 進階設定與除錯

**重點:** Ingress Rewrite、301 Redirect 除錯、IngressClass 版本差異
**date:** 2025-12-09

---

## 1. Ingress 重寫機制 (Rewrite Target)

這是 Nginx Ingress Controller 最核心的功能之一，解決前端路徑與後端應用程式路徑不一致的問題。

### 設定方式
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
```
### 運作原理 (餐廳服務生比喻)

- **情境：** 外部使用者請求 `http://domain/europe`。
- **Ingress (服務生)：** 收到 `/europe`，根據 Annotation 將其塗改 (Rewrite) 為 `/`。
- **Backend Pod (廚房)：** 實際收到的是 `/` (首頁)。
- **目的：** 讓後端程式不需要為了配合 Ingress 的路徑規則 (如 `/europe`) 去修改程式碼，統一處理根路徑即可。

---

## 2. 常見 HTTP 狀態碼除錯：301 Moved Permanently

當 `curl` 或瀏覽器收到 **301** 而非預期的 **200** 或 **404** 時，通常代表 Ingress 正在進行「自動修正」。

### 常見原因

1. **結尾斜線 (Trailing Slash) 自動補全：**    
    - 請求 `/europe` 但 Nginx 判定為目錄，自動轉址到 `/europe/`。

2. **強制 HTTPS (SSL Redirect)：**    
    - 使用 `http://` 訪問，但 Controller 設定強制加密，自動轉址到 `https://`。

### 除錯技巧

使用 `curl -I` (僅查看標頭) 來檢查 `Location` 欄位，確認它想把你轉去哪裡。

```bash
curl -I [http://world.universe.mine:30080/europe](http://world.universe.mine:30080/europe)
# 觀察 output 中的 Location: http://world.universe.mine:30080/europe/
```

---

## 3. Service 端口解析：內外對接

當我們觀察 Ingress Controller 的 Service 時：

80:30080/TCP

|**端口**|**類型**|**意義與連線方式**|
|---|---|---|
|**80**|**Service Port**|**對內 (Internal)**。K8s 叢集內部的 Pod 透過 `ClusterIP:80` 溝通。|
|**30080**|**NodePort**|**對外 (External)**。外部使用者透過 `NodeIP:30080` 連線進入叢集。|

---

## 4. 指定 Controller：IngressClass 的演進

在 YAML 中常看到兩種指定 Controller 的方式，它們同時存在通常是為了 **向下相容 (Backward Compatibility)**。

### 方式比較

| **方式**             | **語法位置**                                                                     | **狀態**              | **說明**                                   |
| ------------------ | ---------------------------------------------------------------------------- | ------------------- | ---------------------------------------- |
| **Annotation (舊)** | `metadata.annotations`<br><br>  <br><br>`kubernetes.io/ingress.class: nginx` | **Deprecated** (過時) | K8s 1.18 之前的做法，透過標籤認領。                   |
| **Spec Field (新)** | `spec.ingressClassName: nginx`                                               | **Standard** (標準)   | K8s 1.19+ 的正式標準，連結到 `IngressClass` 資源物件。 |

- **最佳實踐：** 新版 K8s 應優先使用 `spec.ingressClassName`，但為了支援舊版 Controller 或舊環境，保留 Annotation 也是常見做法。