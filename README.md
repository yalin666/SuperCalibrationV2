# 双目相机全流程标定工具 README

## 1. 项目简介

本项目是一个 **双目相机全流程标定工具**，集成了以下功能：

- 左右目图像对自动匹配
- 标定板图像快速筛选
- 基于 MATLAB 的双目标定优化
- 标定参数自动提取为 Python 可读格式
- 双目图像极线校正
- 生成适用于后续视觉 / SLAM 系统的 `camera_params.yaml`

该工具不是单一的标定脚本，而是一个 **集图像筛选、误差优化、图像校正、参数导出于一体的完整流水线**。

---

## 2. 功能流程

整个流程分为 4 个阶段：

### 阶段 0：图像筛选
脚本会先从左右目文件夹中寻找 **同名图像对**，再使用 OpenCV 检测棋盘格角点，完成：

- 多尺度棋盘格检测
- 左右目同步有效性判断
- 基于空间区域的均衡抽样
- 多样性检查
- 数据不足时随机补图

筛选后的图像会复制到：

- `filtered_left/`
- `filtered_right/`

### 阶段 1：MATLAB 双目标定
调用 MATLAB 中的 `stereo_calibration_optimized(...)` 完成双目标定优化，输出：

- `stereoParams_optimized.mat`

### 阶段 2：提取标定参数
从 `.mat` 文件中提取：

- 左右相机内参矩阵 `K1 / K2`
- 畸变参数 `D1 / D2`
- 旋转矩阵 `R`
- 平移矩阵 `T`
- 图像尺寸 `img_size`

并保存为：

- `calib_params.py`

### 阶段 3：图像校正与 YAML 生成
使用 OpenCV 的 `stereoRectify` 和 `initUndistortRectifyMap` 完成极线校正，并输出：

- `rectified_left/`
- `rectified_right/`
- `camera_params.yaml`
- `baseline_val.txt`

---

## 3. 环境要求

### 3.1 操作系统建议
推荐在 **Linux / Ubuntu** 环境下运行，因为脚本使用了：

- Bash
- `realpath`
- `rm -rf`
- `tee`
- `find`
- `sed`
- MATLAB 命令行接口

理论上 WSL 可以运行，但优先推荐原生 Linux。

### 3.2 必需软件

运行前需要保证以下命令可直接调用：

- `matlab`
- `python3`

若任一命令不存在，脚本会直接退出。

### 3.3 Python 依赖

脚本会检查以下 Python 模块：

- `cv2`
- `numpy`
- `pathlib`
- `shutil`
- `time`
- `multiprocessing`
- `random`
- `tqdm`
- `PIL`

通常需要额外安装的依赖为：

- `opencv-python`
- `numpy`
- `tqdm`
- `Pillow`

---

## 4. 环境安装与配置

### 4.1 安装 Python

以 Ubuntu 为例：

```bash
sudo apt update
sudo apt install -y python3 python3-pip
```

检查：

```bash
python3 --version
pip3 --version
```

### 4.2 安装 Python 依赖

建议提前手动安装：

```bash
pip3 install numpy opencv-python tqdm Pillow
```

### 4.3 安装 MATLAB

需要本机已安装 MATLAB，并且终端可直接调用：

```bash
matlab
```

如果终端提示找不到命令，需要将 MATLAB 加入环境变量。

例如：

```bash
export PATH=/usr/local/MATLAB/R2023b/bin:$PATH
```

为了长期生效，可写入：

```bash
echo 'export PATH=/usr/local/MATLAB/R2023b/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### 4.4 准备 MATLAB 标定函数

脚本会在当前脚本目录或者 `matlab_scripts/` 目录中查找：

```matlab
stereo_calibration_optimized(...)
```

因此你需要准备好该 MATLAB 函数文件。

推荐目录结构如下：

```text
project/
├── run_pipeline.sh
├── stereo_calibration_optimized.m
```

或者：

```text
project/
├── run_pipeline.sh
└── matlab_scripts/
    └── stereo_calibration_optimized.m
```

---

## 5. 数据准备格式

左右目图像必须分别放在两个文件夹中，并且 **左右图像文件名必须一致**，脚本会根据同名文件完成配对。

例如：

```text
dataset/
├── left/
│   ├── 0001.png
│   ├── 0002.png
│   ├── 0003.png
│   └── ...
└── right/
    ├── 0001.png
    ├── 0002.png
    ├── 0003.png
    └── ...
```

支持的图像格式包括：

- `.jpg`
- `.jpeg`
- `.png`
- `.bmp`

---

## 6. 运行方式

### 6.1 给脚本执行权限

```bash
chmod +x run_pipeline.sh
```

### 6.2 基本运行命令

```bash
./run_pipeline.sh -l ./left -r ./right
```

### 6.3 指定输出目录和方格尺寸

```bash
./run_pipeline.sh \
  -l ./left \
  -r ./right \
  -s 30.0 \
  -o ./results_optimized
```

---

## 7. 参数说明

## 7.1 必需参数

### `-l, --left <path>`
左相机图像文件夹路径。

示例：

```bash
-l ./data/left
```

### `-r, --right <path>`
右相机图像文件夹路径。

示例：

```bash
-r ./data/right
```

这两个参数必须同时提供。

---

## 7.2 基础可选参数

### `-s, --square <size>`
标定板单个方格的实际尺寸，单位为 **mm**。

默认值：

```bash
30.0
```

示例：

```bash
-s 25.0
```

作用：用于 MATLAB 双目标定时构建真实世界坐标。

### `-o, --output <path>`
输出文件夹路径。

默认值：

```bash
./results_optimized
```

示例：

```bash
-o ./output_calib
```

注意：脚本运行时会清空该输出目录中的历史内容，但带有安全保护机制。

### `-m, --min-images <num>`
最少保留图像数。

默认值：

```bash
40
```

示例：

```bash
-m 50
```

作用：传递给 MATLAB 标定优化函数，控制最少参与优化的图像数。

---

## 7.3 图像筛选参数

### `-f, --filter-target <num>`
筛选目标图像数量。

默认值：

```bash
300
```

示例：

```bash
-f 200
```

作用：控制前置筛选阶段最终期望保留的图像对数量。

### `--filter-pattern <w,h>`
棋盘格内角点数量，格式为：

```bash
(列数,行数)
```

默认值：

```bash
(11,8)
```

示例：

```bash
--filter-pattern "(9,6)"
```

注意：这里是 **内角点数量**，不是方格数量。

### `--filter-no-parallel`
禁用并行处理。

默认状态下脚本会采用并行处理图像筛选，加上该参数后会切换为串行。

### `--filter-strict`
严格模式，只保留检测到标定板的图像。

默认值：关闭。

开启后，若有效标定图数量不足，脚本不会随机补图。

### `--filter-diversity <val>`
最小多样性阈值。

默认值：

```bash
0.3
```

示例：

```bash
--filter-diversity 0.25
```

作用：限制某一区域图像占比过高，避免筛选结果空间分布过于集中。

---

## 7.4 标定筛选参数

这些参数会传给 MATLAB 标定函数 `stereo_calibration_optimized(...)`。

### `-t, --threshold <factor>`
误差阈值系数。

默认值：

```bash
1.5
```

示例：

```bash
-t 2.0
```

作用：控制重投影误差的剔除阈值。

### `-n, --target-images <num>`
目标保留图像数量。

示例：

```bash
-n 80
```

### `-e, --target-error <val>`
目标平均误差，单位为像素。

示例：

```bash
-e 0.3
```

### `--percentile <value>`
百分位数阈值。

默认值：

```bash
75
```

示例：

```bash
--percentile 80
```

### `--use-percentile`
启用百分位数阈值模式。

示例：

```bash
--use-percentile
```

### `--strategy <type>`
图像选择策略。

可选值：

- `best`
- `distributed`
- `hybrid`

默认值：

```bash
best
```

示例：

```bash
--strategy hybrid
```

### `-h, --help`
显示帮助信息。

```bash
./run_pipeline.sh -h
```

---

## 8. 推荐命令示例

### 8.1 最简运行

```bash
./run_pipeline.sh -l ./left -r ./right
```

### 8.2 常规推荐配置

```bash
./run_pipeline.sh \
  -l ./left \
  -r ./right \
  -s 30.0 \
  -o ./results_optimized \
  -f 300 \
  --filter-pattern "(11,8)" \
  --filter-diversity 0.3 \
  -m 40 \
  -t 1.5 \
  --strategy hybrid
```

### 8.3 严格筛选模式

```bash
./run_pipeline.sh \
  -l ./left \
  -r ./right \
  -s 30.0 \
  --filter-strict \
  -f 200 \
  --strategy best
```

### 8.4 使用百分位数误差筛选

```bash
./run_pipeline.sh \
  -l ./left \
  -r ./right \
  --use-percentile \
  --percentile 80 \
  --strategy distributed
```

---

## 9. 输出文件说明

成功运行后，输出目录中通常会包含：

```text
results_optimized/
├── analysis/
├── filtered_left/
├── filtered_right/
├── rectified_left/
├── rectified_right/
├── image_filter.py
├── stereo_calibrate_rectify.py
├── filtering.log
├── calibration.log
├── stereoParams_optimized.mat
├── calib_params.py
├── camera_params.yaml
└── baseline_val.txt
```

### 文件说明

#### `filtered_left/` 与 `filtered_right/`
筛选后参与标定的图像对。

#### `rectified_left/` 与 `rectified_right/`
极线校正后的左右图像。

#### `filtering.log`
图像筛选阶段日志。

#### `calibration.log`
MATLAB 标定及后续处理日志。

#### `stereoParams_optimized.mat`
MATLAB 输出的双目标定结果。

#### `calib_params.py`
从 `.mat` 中提取的 Python 标定参数文件。

#### `camera_params.yaml`
最终导出的 YAML 配置文件，可供 ORB-SLAM 或其他双目视觉系统使用。

#### `baseline_val.txt`
双目物理基线值。

---

## 10. 设计特点说明

### 10.1 图像筛选不是简单保留
前置筛选阶段不仅检测到棋盘格就保留，还执行了：

1. 多尺度检测
2. 左右目有效性验证
3. 按空间区域分桶
4. 均衡轮询抽样
5. 多样性校验
6. 必要时重分配或随机补图

因此最终保留的图像更有利于稳定标定。

### 10.2 输出目录安全保护
脚本会禁止清空以下危险路径：

- 根目录 `/`
- 用户主目录 `$HOME`
- 当前工作目录

这样可以避免误删数据。

### 10.3 中文路径兼容
图像读取采用字节流配合 `cv2.imdecode` 的方式，对中文路径更友好。

---

## 11. 常见问题

### 11.1 提示“未找到 MATLAB”
原因：MATLAB 未安装，或者未加入环境变量。

解决：

```bash
matlab
```

如果仍然无法识别，请检查 PATH 设置。

### 11.2 提示“图像文件夹不存在”
原因：`-l` 或 `-r` 指定的目录错误。

解决：

```bash
ls ./left
ls ./right
```

### 11.3 检测率很低
优先检查：

1. `--filter-pattern` 是否正确
2. 图像是否模糊、过曝或反光
3. 棋盘格是否被遮挡
4. 左右图像是否真正一一对应

### 11.4 输出目录内容被清空
这是脚本默认行为，用于避免历史结果干扰。

建议每次实验使用不同输出目录，例如：

```bash
-o ./results_exp01
-o ./results_exp02
```

---

## 12. 总结

本工具适用于双目相机离线标定、极线校正与参数导出任务，尤其适合后续接入：

- ORB-SLAM
- 双目测距
- 立体匹配
- 三维重建
- 双目视觉感知系统

使用前请确保：

- MATLAB 已正确安装并配置环境变量
- `stereo_calibration_optimized.m` 已准备好
- 左右目标定图像命名严格对应
- 棋盘格内角点参数与实际一致
