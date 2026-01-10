# Kubernetes CKA 學習筆記 Part8 - RBAC 權限管理實戰

**重點:** User vs SA、Role vs ClusterRole、綁定作用域 (Scope) 解析  
**date:** 2025-12-15

---

## 1. 核心邏輯：RBAC 黃金三角

權限管理由三個要素組成：**Who (誰) + What (做什麼) + Where (在哪裡)**

| 元件 | 角色比喻 | 功能定義 |
| :--- | :--- | :--- |
| **User / ServiceAccount** | **員工 (Who)** | **User:** 真人或外部系統 (K8s 無此物件，由憑證管理)。<br>**ServiceAccount:** 機器人 (K8s 資源物件，Pod 專用)。 |
| **Role / ClusterRole** | **職位說明書 (What)** | **Role:** 定義單一 Namespace 能做的動作 (Local)。<br>**ClusterRole:** 定義全叢集通用的動作模板 (Global)。 |
| **Binding** | **聘書 (Where)** | **決定權限生效的範圍 (Scope)**。<br>**RoleBinding:** 權限只在該 Namespace 生效。<br>**ClusterRoleBinding:** 權限在全叢集生效。 |

### ⚠️ 關鍵觀念修正
* **ClusterRole 不等於 Global 權限**：它只是一份「通用的規則書」。
* **Binding 才是關鍵**：
    * `ClusterRole` + `RoleBinding` = **Local 權限** (拿總公司的規則，管分店的事)。
    * `ClusterRole` + `ClusterRoleBinding` = **Global 權限** (拿總公司的規則，管總公司的事)。

---

## 2. 常用作答指令 (Imperative Commands)

考試技巧：盡量用 CLI 生成 YAML，避免手寫。

### A. 建立身分 (Identity)

```bash
# 建立 ServiceAccount (機器人)
k -n ns1 create sa pipeline

# User (真人) 不需要建立指令，直接在 Binding 時指定 --user 即可
````

### B. 建立規則 (Roles)

```bash
# 1. 建立 Role (Local): 只在 applications ns 有效
k -n applications create role smoke --verb=create,delete --resource=pods,deployments,sts

# 2. 建立 ClusterRole (Global Template): 定義通用規則
k create clusterrole deployment-manager --verb=create,delete --resource=deployments
```

### C. 建立綁定 (Bindings) - 最重要！

```bash
# 情境 1: 給 Local User 本地權限 (Role + RoleBinding)
# 語法: --role (接本地 Role)
k -n applications create rolebinding smoke-binding --role=smoke --user=smoke

# 情境 2: 給 Local User 通用規則權限 (ClusterRole + RoleBinding)
# 語法: --clusterrole (接通用 Role，如內建的 view)
# 效果: smoke 只能在 default ns 裡查看，不能看別人的
k -n default create rolebinding smoke-view --clusterrole=view --user=smoke

# 情境 3: 給 Admin 全叢集權限 (ClusterRole + ClusterRoleBinding)
# 語法: --clusterrole (接通用 Role)
# 效果: pipeline 可以在所有 Namespace 查看
k create clusterrolebinding pipeline-view-global --clusterrole=view --serviceaccount=ns1:pipeline
```

---

## 3. 參數陷阱解析

### `--user` vs `--serviceaccount`

- **`--user <name>`**: 用於綁定 **User**。K8s 裡沒有 User 物件，直接指定名字即可。
    
- **`--serviceaccount <namespace>:<name>`**: 用於綁定 **ServiceAccount**。必須指定 Namespace，因為 SA 是跑在特定 Namespace 裡的。
### Namespace 的可見性

- `k -n app create role smoke`: 這個 Role 只有在 `app` Namespace 裡看得到。其他 Namespace 無法綁定它。
- 若要多個 Namespace 共用同一套規則，請建立 **ClusterRole**。

---

## 4. 測試與驗證指令 (`auth can-i`)

這是 CKA 拿分關鍵，做完設定務必檢查。

### 語法結構

`k auth can-i <VERB> <RESOURCE> --as <USER_TYPE> -n <NAMESPACE>`

### 實戰範例

```bash
# 1. 檢查 User "smoke" 能否在 applications ns 建立 deployment
k auth can-i create deployments --as smoke -n applications

# 2. 檢查 SA "pipeline" (位於 ns1) 能否跨 Namespace 查看 Pods
# 注意 SA 的格式: system:serviceaccount:<ns>:<name>
k auth can-i list pods --as system:serviceaccount:ns1:pipeline -A

# 3. 負向檢查 (確認權限沒有溢出)
# 檢查 smoke 是否真的不能在 kube-system 裡查看
k auth can-i list pods --as smoke -n kube-system # 預期要回傳 no
```