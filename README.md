# Kubernetes CKA 學習旅程 (2026) 🚀

![Kubernetes](https://img.shields.io/badge/kubernetes-v1.32-blue)
![License](https://img.shields.io/badge/license-MIT-green)

這是一個紀錄從 K8s 初學者到準備 CKA (Certified Kubernetes Administrator) 認證的學習倉庫。

## 📖 專案概述 (Project Overview) 

本專案旨在構建一個高可維護性、結構化的 Kubernetes 技術知識庫。 

## 📂 專案結構

```bash
. 
├── content/      # [Production] 內容會隨著學習進度不斷重構與修正 (Hugo Content)  
│   ├── 00-guide/            # 學習指南與底層觀念整合 
│   ├── 01-architecture/     # 架構原理 (Control Plane, Etcd, Node Management) 
│   ├── 02-workloads/        # 工作負載與調度 (Pod, Deployment, DaemonSet) 
│   ├── 03-networking/       # 網路模型 (Service, Ingress, NetworkPolicy) 
│   └── 05-troubleshooting/  # 除錯 SOP 與案例分析 
├── labs/         # [Staging] CKA 模擬實驗與 YAML 配置檔 
├── static/       # 靜態資源 (架構圖, 截圖) 
├── archive/      # [Local Only] 早期手動部署日誌
└── .gitignore    # 資安邊界定義
```

## 🔧 版控策略 (Git Workflow)

- 本專案採用 **Trunk-based** 概念，記錄每日學習的快照 (Snapshot)。
- **關於內容重複：** 您可能會發現部分筆記內容在不同階段會有重疊，這代表了該知識點在不同學習階段的複習與深化 (Refinement)，真實反映了學習曲線。

## 🔜 未來規劃 (Future Work)

- [ ] 整合 **Hugo** 靜態網站生成器，將 `/content` 部署為技術部落格。

