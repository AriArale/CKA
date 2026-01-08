#!/bin/bash

# 獲取當前日期
DATE=$(date +%Y-%m-%d)

# 讓使用者輸入今天的學習主題
echo "Enter the topic for today:"
read TOPIC

# 執行 Git 流程
echo "Starting upload process..."
git add .
git commit -m "docs: daily update $DATE - $TOPIC"
git push

echo "Upload complete! One step closer to your goal."
