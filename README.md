# 相机双目标定程序

## 1\. 功能

这个脚本用于完成双目相机标定全流程，主要包括：

* 自动匹配左右目同名图像
* 自动筛选适合标定的棋盘格图像
* 调用 MATLAB 做双目标定优化
* 提取内参、畸变、外参
* 生成校正后的左右图像
* 生成 `camera\_params.yaml` 供双目视觉 / SLAM 使用

\---

## 2\. 环境配置

### 2.1 新建 conda 环境

```bash
conda create -n stereo\_calib python=3.10 -y
conda activate stereo\_calib
```

### 2.2 安装 Python 依赖

```bash
pip install numpy opencv-python tqdm Pillow
```

### 2.3 MATLAB 配置

需要本机安装 MATLAB，并且终端可以直接执行：

```bash
matlab
```

如果不行，就把 MATLAB 加到环境变量，例如：

```bash
export PATH=/usr/local/MATLAB/R2023b/bin:$PATH
```

## 3\. 数据准备

左右目图像放到两个文件夹，文件名必须一一对应，例如：

```text
dataset/
├── left/
│   ├── 0001.png
│   ├── 0002.png
└── right/
    ├── 0001.png
    ├── 0002.png
```

支持格式：

* jpg
* jpeg
* png
* bmp

\---

## 4\. 怎么用

### 4.1 赋予执行权限

```bash
chmod +x SuperCalibrationV2.sh.sh
```

### 4.2 最简单运行

```bash
./SuperCalibrationV2.sh -l ./left -r ./right
```

### 4.3 常用运行方式

```bash
./SuperCalibrationV2.sh.sh \\\\
  -l ./left \\\\
  -r ./right \\\\
  -s 30.0 \\\\
  -o ./results\\\_optimized \\\\
  -f 300 \\\\
  --filter-pattern "(11,8)" \\\\
  -m 40 \\\\
  -t 1.5 \\\\
  --strategy hybrid
```

\---

## 5\. 常用参数

### 必填参数

* `-l, --left`：左目图像文件夹
* `-r, --right`：右目图像文件夹

### 常用可选参数

* `-s, --square`：棋盘格方格尺寸，单位 mm，默认 `30.0`
* `-o, --output`：输出目录，默认 `./results\_optimized`
* `-f, --filter-target`：筛选目标图像数量，默认 `300`
* `--filter-pattern`：棋盘格内角点数量，默认 `(11,8)`
* `-m, --min-images`：最少保留图像数，默认 `40`
* `-t, --threshold`：误差阈值系数，默认 `1.5`
* `--strategy`：图像选择策略，可选 `best / distributed / hybrid`
* `--filter-strict`：严格模式，只保留检测到棋盘格的图像
* `--use-percentile`：启用百分位误差筛选
* `--percentile`：百分位阈值，默认 `75`
* `-m`： --min-images 最少保留图像数，默认 40
* `-e`： --target-error 目标平均误差
* `--filter-diversity`：最小多样性阈值，默认 0.3

查看完整参数：

```bash
./SuperCalibrationV2.sh -h
```

\---

## 6\. 运行后会生成什么

输出目录中通常会生成：

```text
results\_optimized/
├── filtered\_left/              # 筛选后的左目图像
├── filtered\_right/             # 筛选后的右目图像
├── rectified\_left/             # 校正后的左目图像
├── rectified\_right/            # 校正后的右目图像
├── stereoParams\_optimized.mat  # MATLAB 标定结果
├── calib\_params.py             # 提取后的 Python 参数
├── camera\_params.yaml          # 最终相机配置文件
├── baseline\_val.txt            # 双目基线值
├── filtering.log               # 图像筛选日志
└── calibration.log             # 标定日志
```

\---

## 7\. 脚本主要做了什么

运行后，脚本会按顺序执行：

1. 检查 MATLAB 和 Python 环境
2. 检查并安装缺失的 Python 依赖
3. 清空旧输出目录
4. 自动筛选左右目标定图像
5. 调用 MATLAB 完成双目标定
6. 提取标定参数到 Python
7. 进行极线校正
8. 生成 YAML 配置文件

\---

## 8\. 注意事项

* 左右目图像文件名必须一致
* `--filter-pattern` 必须和实际棋盘格内角点一致
* 输出目录会被清空，不要设置到重要目录
* 必须有 `stereo\_calibration\_optimized.m`
* 必须能在终端直接调用 `matlab`

\---

## 9\. 一条推荐命令

```bash
conda activate stereo\_calib

./SuperCalibrationV2.sh \\\\
  -l ./dataset/left \\\\
  -r ./dataset/right \\\\
  -s 30 \\\\
  -o ./results\\\_optimized \\\\
  -f 300 \\\\
  --filter-pattern "(11,8)" \\\\
  -m 40 \\\\
  -e 0.5 \\\\
  --strategy hybrid
```

