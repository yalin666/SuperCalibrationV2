#!/bin/bash

# ==============================================================================
# 双目相机全流程标定工具 (带图像筛选与安全清理)
# ==============================================================================

# 颜色与样式定义
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'

# 标准化日志输出函数
log_info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $1"; }
log_stage()   { echo -e "\n${PURPLE}${BOLD}>>> [STAGE $1] $2 ${RESET}"; }

# 默认参数
SQUARE_SIZE=30.0
OUTPUT_DIR="./results_optimized"
ERROR_THRESHOLD=1.5
MIN_IMAGES=40
TARGET_IMAGES=""
TARGET_ERROR=""
SELECTION_STRATEGY="best"
USE_PERCENTILE=false
PERCENTILE=75
PYTHON_SCRIPT_NAME="stereo_calibrate_rectify.py"
# 图像筛选参数
FILTER_TARGET_COUNT=300
FILTER_USE_PARALLEL=true
FILTER_STRICT_MODE=false
FILTER_MIN_DIVERSITY=0.3
FILTER_PATTERN_SIZE="(11,8)"  # 标定板内角点数量

# 显示帮助信息
show_help() {
    echo -e "${BOLD}${BLUE}双目相机优化标定+校正+YAML生成工具 - 带图像筛选功能${RESET}"
    echo ""
    echo "用法: $0 -l <左相机图像文件夹> -r <右相机图像文件夹> [选项]"
    echo ""
    echo -e "${BOLD}必需参数:${RESET}"
    echo "  -l, --left <path>          左相机图像文件夹"
    echo "  -r, --right <path>         右相机图像文件夹"
    echo ""
    echo -e "${BOLD}可选参数:${RESET}"
    echo "  -s, --square <size>        标定板方格大小(mm),默认: ${SQUARE_SIZE}"
    echo "  -o, --output <path>        输出文件夹,默认: ${OUTPUT_DIR}"
    echo "  -m, --min-images <num>     最少保留图像数,默认: ${MIN_IMAGES}"
    echo ""
    echo -e "${PURPLE}${BOLD}图像筛选参数:${RESET}"
    echo "  -f, --filter-target <num>  筛选目标图像数量,默认: ${FILTER_TARGET_COUNT}"
    echo "  --filter-pattern <w,h>     标定板内角点数量(列,行),默认: ${FILTER_PATTERN_SIZE}"
    echo "  --filter-no-parallel       禁用并行处理"
    echo "  --filter-strict            严格模式(只保留检测到标定板的图像)"
    echo "  --filter-diversity <val>   最小多样性阈值(0-1),默认: ${FILTER_MIN_DIVERSITY}"
    echo ""
    echo -e "${PURPLE}${BOLD}标定筛选参数:${RESET}"
    echo "  -t, --threshold <factor>   误差阈值系数(σ的倍数),默认: ${ERROR_THRESHOLD}"
    echo "  -n, --target-images <num>  目标保留图像数量"
    echo "  -e, --target-error <val>   目标平均误差(像素)"
    echo "  --percentile <value>       使用百分位数阈值(0-100)"
    echo "  --use-percentile           启用百分位数阈值模式"
    echo "  --strategy <type>          图像选择策略: best/distributed/hybrid"
    echo ""
    echo "  -h, --help                 显示此帮助信息"
}

# 解析命令行参数
LEFT_DIR=""
RIGHT_DIR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--left) LEFT_DIR="$2"; shift 2 ;;
        -r|--right) RIGHT_DIR="$2"; shift 2 ;;
        -s|--square) SQUARE_SIZE="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -t|--threshold) ERROR_THRESHOLD="$2"; shift 2 ;;
        -m|--min-images) MIN_IMAGES="$2"; shift 2 ;;
        -n|--target-images) TARGET_IMAGES="$2"; shift 2 ;;
        -e|--target-error) TARGET_ERROR="$2"; shift 2 ;;
        --percentile) PERCENTILE="$2"; shift 2 ;;
        --use-percentile) USE_PERCENTILE=true; shift ;;
        --strategy) SELECTION_STRATEGY="$2"; shift 2 ;;
        # 图像筛选参数
        -f|--filter-target) FILTER_TARGET_COUNT="$2"; shift 2 ;;
        --filter-pattern) FILTER_PATTERN_SIZE="$2"; shift 2 ;;
        --filter-no-parallel) FILTER_USE_PARALLEL=false; shift ;;
        --filter-strict) FILTER_STRICT_MODE=true; shift ;;
        --filter-diversity) FILTER_MIN_DIVERSITY="$2"; shift 2 ;;
        # 帮助
        -h|--help) show_help; exit 0 ;;
        *) log_error "未知参数 $1"; show_help; exit 1 ;;
    esac
done

# 检查必需参数和依赖
if [ -z "$LEFT_DIR" ] || [ -z "$RIGHT_DIR" ]; then
    log_error "必须指定左右相机图像文件夹"
    show_help; exit 1
fi
if [ ! -d "$LEFT_DIR" ] || [ ! -d "$RIGHT_DIR" ]; then
    log_error "图像文件夹不存在"
    exit 1
fi
if ! command -v matlab &> /dev/null; then
    log_error "未找到MATLAB（需安装并配置环境变量）"
    exit 1
fi
if ! command -v python3 &> /dev/null; then
    log_error "未找到Python3（需安装并配置环境变量）"
    exit 1
fi

# 检查并安装Python依赖
log_info "检查 Python 依赖与环境..."
REQUIRED_PACKAGES=("cv2" "numpy" "pathlib" "shutil" "time" "multiprocessing" "random" "tqdm" "PIL")
MISSING_PACKAGES=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! python3 -c "import $pkg" &> /dev/null; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    log_warn "缺少依赖包: ${MISSING_PACKAGES[*]}，正在静默安装..."
    PIP_PACKAGES=()
    for pkg in "${MISSING_PACKAGES[@]}"; do
        case $pkg in
            cv2) PIP_PACKAGES+=("opencv-python") ;;
            PIL) PIP_PACKAGES+=("Pillow") ;;
            *) PIP_PACKAGES+=("$pkg") ;;
        esac
    done
    python3 -m pip install "${PIP_PACKAGES[@]}" --quiet
fi

# ==================== 清空整个输出文件夹（带安全锁） ====================
# 获取绝对路径用于安全比对
REAL_OUTPUT=$(realpath -m "$OUTPUT_DIR")
REAL_HOME=$(realpath "$HOME")
REAL_PWD=$(realpath "$(pwd)")

# 安全检查：绝对禁止清空根目录、用户主目录或当前运行目录
if [ "$REAL_OUTPUT" = "/" ] || [ "$REAL_OUTPUT" = "$REAL_HOME" ] || [ "$REAL_OUTPUT" = "$REAL_PWD" ]; then
    log_error "触发安全限制！禁止清空根目录、主目录或当前工作目录 (${REAL_OUTPUT})。"
    log_warn "请指定一个专用的子文件夹作为输出目录，例如: ./results_optimized"
    exit 1
fi

if [ -d "$OUTPUT_DIR" ]; then
    log_info "正在清空历史输出文件夹以避免干扰: $OUTPUT_DIR ..."
    # ${OUTPUT_DIR:?} 是一种 Bash 安全机制：如果该变量为空，脚本会立即报错停止
    rm -rf "${OUTPUT_DIR:?}"/*
fi
# ============================================================================

# 初始化目录
mkdir -p "$OUTPUT_DIR" "$OUTPUT_DIR/analysis" "$OUTPUT_DIR/rectified_left" "$OUTPUT_DIR/rectified_right"
LEFT_DIR=$(realpath "$LEFT_DIR")
RIGHT_DIR=$(realpath "$RIGHT_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
SCRIPT_DIR=$(dirname $(realpath "$0"))
MATLAB_PATH="$SCRIPT_DIR"
[ -d "$SCRIPT_DIR/matlab_scripts" ] && MATLAB_PATH="$SCRIPT_DIR/matlab_scripts"

# 筛选后的图像目录
FILTERED_LEFT="$OUTPUT_DIR/filtered_left"
FILTERED_RIGHT="$OUTPUT_DIR/filtered_right"
mkdir -p "$FILTERED_LEFT" "$FILTERED_RIGHT"

# 显示配置信息
echo -e "\n${BOLD}${BLUE}======================================================${RESET}"
echo -e "${BOLD}${BLUE}          [ Stereo Calibration Pipeline ]             ${RESET}"
echo -e "${BOLD}${BLUE}======================================================${RESET}"
echo -e " 🗂️  ${BOLD}工作空间:${RESET} $OUTPUT_DIR"
echo -e " 📷 ${BOLD}左目图源:${RESET} $LEFT_DIR"
echo -e " 📷 ${BOLD}右目图源:${RESET} $RIGHT_DIR"
echo -e " 📐 ${BOLD}标定尺寸:${RESET} ${SQUARE_SIZE} mm, 角点 ${FILTER_PATTERN_SIZE}"
echo -e " 🔍 ${BOLD}筛选配置:${RESET} 目标 ${FILTER_TARGET_COUNT} 张, 严格模式 ${FILTER_STRICT_MODE}"
echo -e "${BOLD}${BLUE}======================================================${RESET}\n"

# ==============================================================================
# 步骤0: 执行图像筛选
# ==============================================================================
log_stage "0/3" "执行标定板图像快速筛选"
FILTER_LOG="$OUTPUT_DIR/filtering.log"

# 创建临时Python筛选脚本
FILTER_SCRIPT="$OUTPUT_DIR/image_filter.py"
cat > "$FILTER_SCRIPT" << EOF
import os
import cv2
import numpy as np
from pathlib import Path
import shutil
import time
from multiprocessing import Pool, cpu_count
import random
from tqdm import tqdm
from PIL import Image

# ================= 注入日志美化类 =================
class Log:
    CYAN = '\033[0;36m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    RESET = '\033[0m'
    BOLD = '\033[1m'
    
    @staticmethod
    def info(msg): print(f"{Log.CYAN}[INFO]{Log.RESET} {msg}")
    @staticmethod
    def success(msg): print(f"{Log.GREEN}[SUCCESS]{Log.RESET} {msg}")
    @staticmethod
    def warn(msg): print(f"{Log.YELLOW}[WARN]{Log.RESET} {msg}")
    @staticmethod
    def error(msg): print(f"{Log.RED}[ERROR]{Log.RESET} {msg}")
# ==================================================

class FastCalibrationImageSelector:
    def __init__(self, left_folder, right_folder, output_folder=None):
        self.left_folder = Path(left_folder)
        self.right_folder = Path(right_folder)
        self.output_folder = Path(output_folder) if output_folder else None

        # 棋盘格参数 - 从命令行传入
        self.pattern_size = $FILTER_PATTERN_SIZE  # 内角点数量 (columns, rows)

        # 添加检测参数
        self.detection_flags = cv2.CALIB_CB_ADAPTIVE_THRESH + cv2.CALIB_CB_NORMALIZE_IMAGE
        self.detection_flags_fast = cv2.CALIB_CB_FAST_CHECK

        # 多尺度检测参数
        self.scale_factors = [0.8, 0.5, 0.3]  # 多尺度检测，从大到小

        # 区域定义
        self.regions = {
        'top_left': (0, 0, 0.45, 0.45),      
        'top_right': (0.55, 0, 0.45, 0.45),  # 0.55 起始，留一点中间缝隙
        'bottom_left': (0, 0.55, 0.45, 0.45),
        'bottom_right': (0.55, 0.55, 0.45, 0.45),
        'center': (0.3, 0.3, 0.4, 0.4)       # 中心区域也可以稍微扩大
    }

        self.selected_pairs = []
        self.all_detected_pairs = []  # 存储所有检测到标定板的图像对
        self.all_image_pairs = []  # 存储所有图像对

    def get_image_pairs(self):
        """获取左右目图像对"""
        left_images = sorted([f.name for f in self.left_folder.iterdir()
                              if f.suffix.lower() in ['.jpg', '.jpeg', '.png', '.bmp']])
        right_images = sorted([f.name for f in self.right_folder.iterdir()
                               if f.suffix.lower() in ['.jpg', '.jpeg', '.png', '.bmp']])

        common_files = set(left_images) & set(right_images)
        pairs = []
        for filename in sorted(common_files):
            pairs.append((self.left_folder / filename, self.right_folder / filename))

        return pairs

    def read_image_safe(self, image_path):
        """安全读取图像，处理中文路径问题"""
        try:
            path_str = str(image_path)
            with open(path_str, 'rb') as f:
                image_bytes = np.frombuffer(f.read(), np.uint8)
            img = cv2.imdecode(image_bytes, cv2.IMREAD_GRAYSCALE)
            return img
        except Exception as e:
            Log.error(f"读取图像失败 {image_path}: {e}")
            return None

    def preprocess_image(self, img):
        """图像预处理，增强标定板检测"""
        if img is None:
            return None

        # 应用直方图均衡化，增强对比度
        img_eq = cv2.equalizeHist(img)

        return img_eq

    def detect_checkerboard_multi_scale(self, img, fast_check=True):
        """多尺度检测标定板 - 提高检测率"""
        if img is None:
            return None

        original_h, original_w = img.shape

        # 尝试不同缩放尺度
        for scale in self.scale_factors:
            new_w, new_h = int(original_w * scale), int(original_h * scale)
            if new_w < 100 or new_h < 100:  # 避免图像过小
                continue

            small_img = cv2.resize(img, (new_w, new_h))

            # 尝试快速检测
            if fast_check:
                ret, corners = cv2.findChessboardCorners(
                    small_img,
                    self.pattern_size,
                    flags=self.detection_flags_fast
                )

                if ret:
                    # 在找到的粗略位置进行亚像素精细化
                    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
                    corners_refined = cv2.cornerSubPix(
                        small_img, corners, (5, 5), (-1, -1), criteria
                    )

                    # 计算中心位置（映射回原始尺寸）
                    center_x = np.mean(corners_refined[:, 0, 0]) / scale
                    center_y = np.mean(corners_refined[:, 0, 1]) / scale
                    return (center_x, center_y)

            # 如果快速检测失败，尝试完整检测
            ret, corners = cv2.findChessboardCorners(
                small_img,
                self.pattern_size,
                flags=self.detection_flags
            )

            if ret:
                # 亚像素精细化
                criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
                corners_refined = cv2.cornerSubPix(
                    small_img, corners, (5, 5), (-1, -1), criteria
                )

                # 计算中心位置
                center_x = np.mean(corners_refined[:, 0, 0]) / scale
                center_y = np.mean(corners_refined[:, 0, 1]) / scale
                return (center_x, center_y)

        # 如果多尺度检测都失败，尝试在预处理后的原始图像上检测
        img_preprocessed = self.preprocess_image(img)
        if img_preprocessed is not None:
            ret, corners = cv2.findChessboardCorners(
                img_preprocessed,
                self.pattern_size,
                flags=self.detection_flags
            )

            if ret:
                # 亚像素精细化
                criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
                corners_refined = cv2.cornerSubPix(
                    img_preprocessed, corners, (5, 5), (-1, -1), criteria
                )

                # 计算中心位置
                center_x = np.mean(corners_refined[:, 0, 0])
                center_y = np.mean(corners_refined[:, 0, 1])
                return (center_x, center_y)

        return None

    def fast_detect_checkerboard(self, image_path):
        """快速检测标定板 - 优化版本，提高检测率"""
        # 读取图像
        img = self.read_image_safe(image_path)
        if img is None:
            return None

        # 使用多尺度检测
        result = self.detect_checkerboard_multi_scale(img, fast_check=True)

        # 如果失败，尝试另一种检测策略
        if result is None:
            # 尝试不进行快速检测的完整检测
            result = self.detect_checkerboard_multi_scale(img, fast_check=False)

        return result

    def get_image_size(self, image_path):
        """获取图像尺寸"""
        try:
            with Image.open(image_path) as img:
                return img.size  # (width, height)
        except:
            try:
                img_data = self.read_image_safe(image_path)
                if img_data is not None:
                    return (img_data.shape[1], img_data.shape[0])
            except:
                pass
        return None

    def is_in_region(self, point, img_size):
        """检查点是否在目标区域内"""
        x, y = point
        img_w, img_h = img_size

        for region_name, (rx, ry, rw, rh) in self.regions.items():
            region_x1 = rx * img_w
            region_y1 = ry * img_h
            region_x2 = (rx + rw) * img_w
            region_y2 = (ry + rh) * img_h

            if (region_x1 <= x <= region_x2 and region_y1 <= y <= region_y2):
                return region_name

        return None

    def analyze_image_pair_fast(self, left_path, right_path):
        """快速分析图像对中标定板位置"""
        # 获取图像尺寸
        img_size = self.get_image_size(left_path)
        if img_size is None:
            # 尝试直接从图像获取尺寸
            left_img = self.read_image_safe(left_path)
            if left_img is None:
                return False, "无法读取图像"
            img_size = (left_img.shape[1], left_img.shape[0])

        # 快速检测标定板
        left_center = self.fast_detect_checkerboard(left_path)
        if left_center is None:
            return False, "左目图像未检测到标定板"

        right_center = self.fast_detect_checkerboard(right_path)
        if right_center is None:
            return False, "右目图像未检测到标定板"

        # 检查标定板位置
        left_region = self.is_in_region(left_center, img_size)
        right_region = self.is_in_region(right_center, img_size)

        if left_region and right_region:
            return True, {
                'left_region': left_region,
                'right_region': right_region,
                'left_center': left_center,
                'right_center': right_center
            }
        else:
            # 即使不在目标区域，只要检测到标定板就返回成功
            return True, {
                'left_region': left_region if left_region else 'other',
                'right_region': right_region if right_region else 'other',
                'left_center': left_center,
                'right_center': right_center
            }

    def process_batch(self, batch_with_indices):
        """处理一批图像对 - 用于并行处理"""
        batch, start_idx = batch_with_indices
        results = []
        for i, (left_path, right_path) in enumerate(batch):
            success, result = self.analyze_image_pair_fast(left_path, right_path)
            results.append((success, result, left_path, right_path, start_idx + i))
        return results

    def select_images_fast(self, target_count=300, use_parallel=True, strict_mode=False, min_diversity=0.3):
        """快速筛选符合要求的图像对"""
        Log.info("启动快速多尺度空间特征提取...")
        start_time = time.time()

        self.all_image_pairs = self.get_image_pairs()
        Log.info(f"数据总线挂载完毕，共发现 {len(self.all_image_pairs)} 对同步图像。")

        if len(self.all_image_pairs) == 0:
            Log.error("未找到匹配的图像对，流程中断！")
            return False

        # 第一阶段：检测所有图像对
        Log.info("Phase 1/4: 检测所有图像对中的标定特征...")
        self.all_detected_pairs = []

        if use_parallel and len(self.all_image_pairs) > 1:
            num_workers = min(cpu_count(), 8)
            batch_size = max(1, len(self.all_image_pairs) // num_workers)

            Log.info(f"分配 {num_workers} 个工作进程加速处理...")

            # 准备批次数据（包含索引）
            batches_with_indices = []
            for i in range(0, len(self.all_image_pairs), batch_size):
                batch = self.all_image_pairs[i:i + batch_size]
                batches_with_indices.append((batch, i))

            with Pool(processes=num_workers) as pool:
                batch_results = []
                for result in tqdm(pool.imap_unordered(self.process_batch, batches_with_indices),
                                   total=len(batches_with_indices), desc="特征提取进度"):
                    batch_results.append(result)

            # 合并结果
            for batch in batch_results:
                for success, result, left_path, right_path, idx in batch:
                    if success:
                        self.all_detected_pairs.append({
                            'left': left_path,
                            'right': right_path,
                            'regions': (result['left_region'], result['right_region']),
                            'centers': (result['left_center'], result['right_center']),
                            'index': idx,
                            'has_checkerboard': True
                        })
        else:
            # 串行处理
            for i, (left_path, right_path) in enumerate(tqdm(self.all_image_pairs, desc="特征提取进度")):
                success, result = self.analyze_image_pair_fast(left_path, right_path)
                if success:
                    self.all_detected_pairs.append({
                        'left': left_path,
                        'right': right_path,
                        'regions': (result['left_region'], result['right_region']),
                        'centers': (result['left_center'], result['right_center']),
                        'index': i,
                        'has_checkerboard': True
                    })

        Log.success(f"Phase 1 完成，共锁定 {len(self.all_detected_pairs)} 对有效标定图。")

        # 如果检测到的图像过少，打印一些统计信息
        detection_rate = len(self.all_detected_pairs) / len(self.all_image_pairs) if self.all_image_pairs else 0
        
        if detection_rate < 0.3:  # 如果检测率低于30%，可能需要调整参数
            Log.warn(f"当前检测率仅为 {detection_rate:.2%}，建议排查:")
            print("      1. pattern_size 参数是否与实际角点数一致？(当前: {})".format(self.pattern_size))
            print("      2. 标定板是否存在过曝、反光或视场遮挡问题？")

        # ==================== 修改开始 ====================
        Log.info("Phase 2/4: 执行轮询均衡筛选 (Round-Robin Selection)...")
        
        # 1. 将所有候选图像按区域分类放入“桶”中
        buckets = {r: [] for r in self.regions.keys()}
        buckets['other'] = []
        
        # 将所有检测到标定板的图像归类
        for pair in self.all_detected_pairs:
            region = pair['regions'][0]
            # 只有严格模式下排除other，否则都放入对应桶中
            if strict_mode and region == 'other':
                continue
            if region in buckets:
                buckets[region].append(pair)
            else:
                buckets['other'].append(pair) # 防御性代码

        # 2. 对每个桶内的图像进行随机打乱（避免只取时间序列的前几张）
        for region in buckets:
            random.shuffle(buckets[region])

        # 3. 轮询抽取 (Round-Robin)
        self.selected_pairs = []
        region_stats = {r: 0 for r in buckets.keys()}
        region_stats['total'] = 0
        
        # 定义优先级：优先取核心区域，核心取完了再取other
        priority_regions = list(self.regions.keys()) # ['top_left', 'top_right', ...]
        other_regions = ['other']
        
        while len(self.selected_pairs) < target_count:
            added_in_this_round = False
            
            # 3.1 先从核心区域各取一张
            for region in priority_regions:
                if len(self.selected_pairs) >= target_count: break
                if buckets[region]: # 如果这个区域还有图
                    pair = buckets[region].pop(0) # 取出一张
                    self.selected_pairs.append(pair)
                    region_stats[region] += 1
                    region_stats['total'] += 1
                    added_in_this_round = True
            
            # 3.2 如果这一轮核心区域都没图了，或者未凑满，允许从other取（非严格模式）
            if not added_in_this_round and not strict_mode:
                if buckets['other']:
                    pair = buckets['other'].pop(0)
                    self.selected_pairs.append(pair)
                    region_stats['other'] += 1
                    region_stats['total'] += 1
                    added_in_this_round = True
            
            # 如果所有桶都空了，停止
            if not added_in_this_round:
                break
                
        # 按原始索引排序，方便后续处理
        self.selected_pairs.sort(key=lambda x: x['index'])
        # ==================== 修改结束 ====================

        # 第三阶段：如果检测到的图像数量不足，随机选取补足
        if region_stats['total'] < target_count:
            self._supplement_with_random_images(region_stats, target_count, strict_mode)

        # 第四阶段：检查多样性并随机取样
        if region_stats['total'] >= target_count:
            self._check_and_improve_diversity(region_stats, target_count, min_diversity)

        elapsed_time = time.time() - start_time
        Log.success(f"数据清洗组装完毕，总耗时: {elapsed_time:.2f} 秒")

        self.print_statistics(region_stats, target_count)

        if self.output_folder:
            self.save_selected_images()
        
        return len(self.selected_pairs) > 0

    def _supplement_with_random_images(self, region_stats, target_count, strict_mode):
        """当检测到的标定板图像不足时，随机选取图像补足数量"""
        if strict_mode:
            Log.warn(f"严格模式: 检测有效图不足 ({region_stats['total']}/{target_count})，且禁止随机补足。")
            return
            
        Log.info(f"Phase 3/4: 有效标定图不足 ({region_stats['total']}/{target_count})，执行盲盒补足策略...")

        # 获取所有未选中的图像对（包括没有标定板的）
        all_available_pairs = []
        for i, (left_path, right_path) in enumerate(self.all_image_pairs):
            already_selected = any(p['index'] == i for p in self.selected_pairs)
            if not already_selected:
                all_available_pairs.append({
                    'left': left_path,
                    'right': right_path,
                    'regions': ('random', 'random'),
                    'centers': (0, 0),
                    'index': i,
                    'has_checkerboard': False
                })

        # 随机打乱并选择足够的图像
        random.shuffle(all_available_pairs)
        needed_count = target_count - region_stats['total']

        if len(all_available_pairs) >= needed_count:
            supplemental_pairs = all_available_pairs[:needed_count]
        else:
            supplemental_pairs = all_available_pairs
            Log.warn(f"可用盲盒图像耗尽，仅补充 {len(supplemental_pairs)} 张。")

        # 添加补充的图像
        for pair in supplemental_pairs:
            region_stats['random'] = region_stats.get('random', 0) + 1
            region_stats['total'] += 1
            self.selected_pairs.append(pair)

        # 按原始索引排序
        self.selected_pairs.sort(key=lambda x: x['index'])
        Log.success(f"盲盒补足完成，累计追加 {len(supplemental_pairs)} 张。")

    def _check_and_improve_diversity(self, region_stats, target_count, min_diversity):
        """检查多样性并在不足时进行随机间隔取样"""
        Log.info("Phase 4/4: 执行空间分布多样性巡检...")

        # 只考虑有标定板的图像
        checkerboard_pairs = [p for p in self.selected_pairs if p.get('has_checkerboard', False)]
        if len(checkerboard_pairs) == 0:
            Log.warn("数据池内无有效特征图，跳过多样性校验。")
            return

        # 计算每个区域的占比
        total_checkerboard = len(checkerboard_pairs)
        region_ratios = {}
        for region in list(self.regions.keys()) + ['other']:
            region_count = len([p for p in checkerboard_pairs if p['regions'][0] == region])
            if total_checkerboard > 0:
                region_ratios[region] = region_count / total_checkerboard
            else:
                region_ratios[region] = 0

        # 检查是否有区域占比过高
        max_ratio = max(region_ratios.values()) if region_ratios else 0
        diversity_issue = max_ratio > min_diversity

        if diversity_issue:
            Log.warn(f"检测到多样性失衡：某区域聚集度超过警戒线 ({min_diversity * 100:.1f}%)")
            Log.info("触发重新分配机制 (Random Interval Sampling)...")

            checkerboard_only_pairs = [p for p in self.selected_pairs if p.get('has_checkerboard', False)]
            random_only_pairs = [p for p in self.selected_pairs if not p.get('has_checkerboard', False)]

            self.selected_pairs.clear()
            region_stats = {region: 0 for region in list(self.regions.keys()) + ['other', 'random']}
            region_stats['total'] = 0

            # 按区域分组
            region_groups = {}
            for region in list(self.regions.keys()) + ['other']:
                region_groups[region] = [p for p in checkerboard_only_pairs if p['regions'][0] == region]

            # 计算每个区域应该选择的图像数量
            region_targets = {}
            remaining = min(target_count, len(checkerboard_only_pairs))

            # 首先保证每个目标区域至少有1张图像
            for region in list(self.regions.keys()) + ['other']:
                if len(region_groups[region]) > 0:
                    region_targets[region] = 1
                    remaining -= 1
                    if remaining <= 0:
                        break

            # 剩余数量按比例分配
            if remaining > 0:
                total_available = sum(len(region_groups[region]) for region in region_groups.keys())
                for region in region_groups.keys():
                    if len(region_groups[region]) > 0:
                        ratio = len(region_groups[region]) / total_available
                        additional = max(0, int(remaining * ratio))
                        region_targets[region] = region_targets.get(region, 0) + additional
                        remaining -= additional
                        if remaining <= 0:
                            break

            # 从每个区域中随机间隔选择图像
            for region, target in region_targets.items():
                if target > 0 and region in region_groups and len(region_groups[region]) > 0:
                    available_pairs = region_groups[region]
                    if len(available_pairs) > target:
                        step = len(available_pairs) // target
                        selected_indices = list(range(0, len(available_pairs), step))[:target]
                        random.shuffle(selected_indices)
                        selected_indices = sorted(selected_indices[:target])
                    else:
                        selected_indices = range(len(available_pairs))

                    for idx in selected_indices:
                        pair = available_pairs[idx]
                        region_stats[region] += 1
                        region_stats['total'] += 1
                        self.selected_pairs.append(pair)

            # 添加之前随机选择的图像
            for pair in random_only_pairs:
                if region_stats['total'] < target_count:
                    region_stats['random'] += 1
                    region_stats['total'] += 1
                    self.selected_pairs.append(pair)

            # 如果还不够，从所有有标定板的图像中随机选择补足
            if region_stats['total'] < target_count:
                remaining_needed = target_count - region_stats['total']
                all_available = [p for p in checkerboard_only_pairs if p not in self.selected_pairs]
                if len(all_available) > 0:
                    step = max(1, len(all_available) // remaining_needed)
                    additional_pairs = all_available[::step][:remaining_needed]
                    for pair in additional_pairs:
                        region = pair['regions'][0]
                        region_stats[region] += 1
                        region_stats['total'] += 1
                        self.selected_pairs.append(pair)

            # 按原始索引排序
            self.selected_pairs.sort(key=lambda x: x['index'])
            Log.success("空间分布失衡修正完毕。")
        else:
            Log.success("空间分布良好，通过多样性校验。")

    def print_statistics(self, stats, target_count):
        """打印统计信息和建议"""
        print(f"\n{Log.CYAN}╭────────────────────────────────────────────────╮{Log.RESET}")
        print(f"{Log.CYAN}│               📊 空间分布特征简报                │{Log.RESET}")
        print(f"{Log.CYAN}├────────────────────────────────────────────────┤{Log.RESET}")

        total_selected = stats['total']

        # 统计有标定板和随机选择的图像数量
        checkerboard_count = len([p for p in self.selected_pairs if p.get('has_checkerboard', False)])
        random_count = len([p for p in self.selected_pairs if not p.get('has_checkerboard', False)])

        # 打印各个区域的统计
        for region in list(self.regions.keys()) + ['other', 'random']:
            if region in stats and stats[region] > 0:
                ratio = stats[region] / total_selected if total_selected > 0 else 0
                region_name = {
                    'top_left': '左上象限', 'top_right': '右上象限',
                    'bottom_left': '左下象限', 'bottom_right': '右下象限',
                    'center': '中心区域', 'other': '边缘散乱', 'random': '盲盒补偿'
                }.get(region, region)
                print(f"{Log.CYAN}│{Log.RESET}  {region_name:8}: {stats[region]:3} 帧  [{ratio:6.1%}]                {Log.CYAN}│{Log.RESET}")

        print(f"{Log.CYAN}├────────────────────────────────────────────────┤{Log.RESET}")
        print(f"{Log.CYAN}│{Log.RESET}  {'总计容量':8}: {stats['total']:3} 帧 (标定特征:{checkerboard_count:3} | 盲盒:{random_count:3})  {Log.CYAN}│{Log.RESET}")
        print(f"{Log.CYAN}╰────────────────────────────────────────────────╯{Log.RESET}\n")

        if stats['total'] < target_count:
            Log.warn(f"最终输出 {stats['total']} 帧，未达到预设目标 {target_count} 帧。")
        else:
            Log.success(f"已达到预设标定池容量 ({stats['total']} 帧)。")

            if random_count > 0:
                Log.warn(f"当前队列包含 {random_count} 张无特征盲图，建议人工核验或增加原始数据投喂。")

    def save_selected_images(self):
        """保存选中的图像到输出文件夹"""
        if not self.output_folder:
            return

        left_output = self.output_folder / "filtered_left"
        right_output = self.output_folder / "filtered_right"
        left_output.mkdir(parents=True, exist_ok=True)
        right_output.mkdir(parents=True, exist_ok=True)

        Log.info("开始执行磁盘 I/O 镜像克隆...")
        for i, pair in enumerate(tqdm(self.selected_pairs, desc="数据写入进度")):
            try:
                has_cb = "cb" if pair.get('has_checkerboard', False) else "random"
                region_code = pair['regions'][0][:3] if pair.get('has_checkerboard', False) else "rnd"
                # 保持原始文件名，添加前缀以便识别
                original_name = pair['left'].name
                shutil.copy2(pair['left'],
                             left_output / f"selected_{i:04d}_{region_code}_{has_cb}_{original_name}")
                shutil.copy2(pair['right'],
                             right_output / f"selected_{i:04d}_{region_code}_{has_cb}_{original_name}")
            except Exception as e:
                Log.error(f"镜像文件挂载失败: {e}")

        Log.success("物理镜像克隆完毕。")


def main():
    # 从环境变量获取参数
    LEFT_FOLDER = os.environ.get('LEFT_DIR', '')
    RIGHT_FOLDER = os.environ.get('RIGHT_DIR', '')
    OUTPUT_DIR = os.environ.get('OUTPUT_DIR', '')
    TARGET_COUNT = int(os.environ.get('FILTER_TARGET_COUNT', 300))
    USE_PARALLEL = os.environ.get('FILTER_USE_PARALLEL', 'true').lower() == 'true'
    STRICT_MODE = os.environ.get('FILTER_STRICT_MODE', 'false').lower() == 'true'
    MIN_DIVERSITY = float(os.environ.get('FILTER_MIN_DIVERSITY', 0.3))

    if not LEFT_FOLDER or not RIGHT_FOLDER:
        Log.error("严重错误：未传入左右图像数据集根目录。")
        return 1

    # 创建选择器实例
    selector = FastCalibrationImageSelector(LEFT_FOLDER, RIGHT_FOLDER, OUTPUT_DIR)

    # 开始快速筛选
    success = selector.select_images_fast(
        target_count=TARGET_COUNT,
        use_parallel=USE_PARALLEL,
        strict_mode=STRICT_MODE,
        min_diversity=MIN_DIVERSITY
    )

    return 0 if success else 1


if __name__ == "__main__":
    exit(main())
EOF

# 导出环境变量供Python脚本使用
export LEFT_DIR="$LEFT_DIR"
export RIGHT_DIR="$RIGHT_DIR"
export OUTPUT_DIR="$OUTPUT_DIR"
export FILTER_TARGET_COUNT="$FILTER_TARGET_COUNT"
export FILTER_USE_PARALLEL="$FILTER_USE_PARALLEL"
export FILTER_STRICT_MODE="$FILTER_STRICT_MODE"
export FILTER_MIN_DIVERSITY="$FILTER_MIN_DIVERSITY"

# 执行图像筛选
python3 "$FILTER_SCRIPT" 2>&1 | tee -a "$FILTER_LOG"
if [ $? -ne 0 ] || [ $(find "$FILTERED_LEFT" -type f | wc -l) -eq 0 ]; then
    log_error "图像筛选引擎崩溃，工作区执行中断。"
    exit 1
fi
log_success "阶段 0 通过。清洗后挂载点: $FILTERED_LEFT"


# ==============================================================================
# 步骤1: 运行MATLAB标定
# ==============================================================================
log_stage "1/3" "执行基于 MATLAB 的双目重投影误差最小化求解"
LOG_FILE="$OUTPUT_DIR/calibration.log"
MATLAB_CMD="addpath('$MATLAB_PATH'); "
MATLAB_CMD="${MATLAB_CMD}stereo_calibration_optimized('$FILTERED_LEFT', '$FILTERED_RIGHT', $SQUARE_SIZE, '$OUTPUT_DIR', "
MATLAB_CMD="${MATLAB_CMD}'ErrorThreshold', $ERROR_THRESHOLD, 'MinImages', $MIN_IMAGES, "
MATLAB_CMD="${MATLAB_CMD}'SelectionStrategy', '$SELECTION_STRATEGY', 'UsePercentile', $USE_PERCENTILE, "
MATLAB_CMD="${MATLAB_CMD}'Percentile', $PERCENTILE"
[ ! -z "$TARGET_IMAGES" ] && MATLAB_CMD="${MATLAB_CMD}, 'TargetImages', $TARGET_IMAGES"
[ ! -z "$TARGET_ERROR" ] && MATLAB_CMD="${MATLAB_CMD}, 'TargetError', $TARGET_ERROR"
MATLAB_CMD="${MATLAB_CMD}); quit"

log_info "正在后台召唤 MATLAB 求解器，请耐心等待计算收敛..."
matlab -nodisplay -nosplash -r "$MATLAB_CMD" > "$LOG_FILE" 2>&1
if [ ! -f "$OUTPUT_DIR/stereoParams_optimized.mat" ]; then
    log_error "MATLAB 求解失败，未能生成 stereoParams_optimized.mat，请检查特征提取状态。"
    exit 1
fi
log_success "核心标定矩阵求解成功。"


# ==============================================================================
# 步骤2/3: 提取标定参数
# ==============================================================================
log_stage "2/3" "剥离标定矩阵与 Python 生态反序列化"
MATLAB_EXTRACT_CMD="addpath('$MATLAB_PATH'); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}load('$OUTPUT_DIR/stereoParams_optimized.mat'); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}if ~exist('stereoParamsOptimized', 'var'), error('未找到stereoParamsOptimized对象'); end; "

# 提取参数并直接格式化为Python可执行代码
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}img_size = stereoParamsOptimized.CameraParameters1.ImageSize; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}img_size_str = sprintf('(%d, %d)', img_size(2), img_size(1)); "

MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K1 = stereoParamsOptimized.CameraParameters1.IntrinsicMatrix'; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K1_str = sprintf('np.array([[%.12e, 0, %.12e],\\n', K1(1,1), K1(1,3)); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K1_str = [K1_str sprintf('                [0, %.12e, %.12e],\\n', K1(2,2), K1(2,3))]; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K1_str = [K1_str sprintf('                [0, 0, 1]], dtype=np.float64)')]; "

MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K2 = stereoParamsOptimized.CameraParameters2.IntrinsicMatrix'; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K2_str = sprintf('np.array([[%.12e, 0, %.12e],\\n', K2(1,1), K2(1,3)); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K2_str = [K2_str sprintf('                [0, %.12e, %.12e],\\n', K2(2,2), K2(2,3))]; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}K2_str = [K2_str sprintf('                [0, 0, 1]], dtype=np.float64)')]; "

MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}D1 = [stereoParamsOptimized.CameraParameters1.RadialDistortion(1); stereoParamsOptimized.CameraParameters1.RadialDistortion(2); stereoParamsOptimized.CameraParameters1.TangentialDistortion(1); stereoParamsOptimized.CameraParameters1.TangentialDistortion(2); 0]; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}D1_str = sprintf('np.array([%.12e, %.12e, %.12e, %.12e, %.12e], dtype=np.float64)', D1(1), D1(2), D1(3), D1(4), D1(5)); "

MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}D2 = [stereoParamsOptimized.CameraParameters2.RadialDistortion(1); stereoParamsOptimized.CameraParameters2.RadialDistortion(2); stereoParamsOptimized.CameraParameters2.TangentialDistortion(1); stereoParamsOptimized.CameraParameters2.TangentialDistortion(2); 0]; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}D2_str = sprintf('np.array([%.12e, %.12e, %.12e, %.12e, %.12e], dtype=np.float64)', D2(1), D2(2), D2(3), D2(4), D2(5)); "

MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}R = stereoParamsOptimized.RotationOfCamera2'; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}R_str = sprintf('np.array([[%.12e, %.12e, %.12e],\\n', R(1,1), R(1,2), R(1,3)); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}R_str = [R_str sprintf('              [%.12e, %.12e, %.12e],\\n', R(2,1), R(2,2), R(2,3))]; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}R_str = [R_str sprintf('              [%.12e, %.12e, %.12e]], dtype=np.float64)', R(3,1), R(3,2), R(3,3))]; "

MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}T = stereoParamsOptimized.TranslationOfCamera2; "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}T_str = sprintf('np.array([[%.12e], [%.12e], [%.12e]], dtype=np.float64)', T(1), T(2), T(3)); "

# 直接写入格式化好的Python代码
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fid = fopen('$OUTPUT_DIR/calib_params.py', 'w'); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'import numpy as np\\n\\n'); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'img_size = %s\\n\\n', img_size_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'K1 = %s\\n\\n', K1_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'K2 = %s\\n\\n', K2_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'D1 = %s\\n\\n', D1_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'D2 = %s\\n\\n', D2_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'R = %s\\n\\n', R_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fprintf(fid, 'T = %s\\n', T_str); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}fclose(fid); "
MATLAB_EXTRACT_CMD="${MATLAB_EXTRACT_CMD}quit; "

log_info "正在映射矩阵数据到 calib_params.py ..."
# 执行MATLAB参数提取命令
matlab -nodisplay -nosplash -r "$MATLAB_EXTRACT_CMD" >> "$LOG_FILE" 2>&1
if [ ! -f "$OUTPUT_DIR/calib_params.py" ]; then
    log_error "参数桥接失败，数据流中断。"
    exit 1
fi
log_success "矩阵转译完成。"


# ==============================================================================
# 步骤3/3: 执行图像校正并生成YAML
# ==============================================================================
log_stage "3/3" "执行图像极线校正映射与 YAML 部署文件输出"
cat > "$OUTPUT_DIR/$PYTHON_SCRIPT_NAME" << 'EOF'
import os
import cv2
import numpy as np
from calib_params import img_size, K1, K2, D1, D2, R, T

# 内部输出系统
CYAN = '\033[0;36m'
GREEN = '\033[0;32m'
RESET = '\033[0m'

# 配置路径
LEFT_FOLDER = "$FILTERED_LEFT"
RIGHT_FOLDER = "$FILTERED_RIGHT"
OUTPUT_DIR = "$OUTPUT_DIR"
LEFT_OUT = os.path.join(OUTPUT_DIR, "rectified_left")
RIGHT_OUT = os.path.join(OUTPUT_DIR, "rectified_right")
YAML_OUT = os.path.join(OUTPUT_DIR, "camera_params.yaml")
BASELINE_TXT = os.path.join(OUTPUT_DIR, "baseline_val.txt")

# 计算矫正变换
print(f"{CYAN}[INFO]{RESET} 推算极线校正映射矩阵 (Stereo Rectify Map)...")
R1, R2, P1, P2, Q, _, _ = cv2.stereoRectify(K1, D1, K2, D2, img_size, R, T)
left_map1, left_map2 = cv2.initUndistortRectifyMap(K1, D1, R1, P1, img_size, cv2.CV_32FC1)
right_map1, right_map2 = cv2.initUndistortRectifyMap(K2, D2, R2, P2, img_size, cv2.CV_32FC1)

# 批量矫正图像
print(f"{CYAN}[INFO]{RESET} 正在执行源图像去畸变重映射 (Remap)...")
left_images = sorted([f for f in os.listdir(LEFT_FOLDER) if f.endswith(('.png', '.jpg'))])
right_images = sorted([f for f in os.listdir(RIGHT_FOLDER) if f.endswith(('.png', '.jpg'))])
for l_img, r_img in zip(left_images, right_images):
    l_path = os.path.join(LEFT_FOLDER, l_img)
    r_path = os.path.join(RIGHT_FOLDER, r_img)
    left_rect = cv2.remap(cv2.imread(l_path), left_map1, left_map2, cv2.INTER_LINEAR)
    right_rect = cv2.remap(cv2.imread(r_path), right_map1, right_map2, cv2.INTER_LINEAR)
    cv2.imwrite(os.path.join(LEFT_OUT, l_img), left_rect)
    cv2.imwrite(os.path.join(RIGHT_OUT, r_img), right_rect)

# YAML格式化函数
def _fmt_scalar_float_10(x): return f"{float(x):.10f}"
def _fmt_matrix_generic_val(v): return f"{float(v):.12g}"
def _fmt_matrix_P_val(v):
    vf = float(v)
    if abs(vf) == 0.0: return "0.0"
    if abs(vf - 1.0) < 1e-12: return "1.0"
    return f"{vf:.12g}"

def _print_opencv_matrix(f, name, M, use_p_style=False):
    M = np.array(M, dtype=np.float64)
    rows, cols = M.shape
    flat = ", ".join([_fmt_matrix_P_val(v) if use_p_style else _fmt_matrix_generic_val(v) for v in M.reshape(-1)])
    print(f"{name}: !!opencv-matrix", file=f)
    print(f"   rows: {int(rows)}", file=f)
    print(f"   cols: {int(cols)}", file=f)
    print(f"   dt: d", file=f)
    print(f"   data: [{flat}]", file=f)

# 计算并导出 Baseline
P2_corr = P2.copy()
P2_corr[0,3] /= 1000.0
fx, fy, cx, cy = float(P1[0,0]), float(P1[1,1]), float(P1[0,2]), float(P1[1,2])
bf = abs(P2_corr[0,3])
baseline_val = bf / fx  # 两个相除的结果：计算出真实的物理基线 (单位：米)

# 写入临时文件供 Bash 读取显示
with open(BASELINE_TXT, 'w') as f_base:
    f_base.write(f"{baseline_val:.6f}")

width, height = img_size

# 生成YAML文件
with open(YAML_OUT, 'w') as f:
    print("%YAML:1.0\n", file=f)
    print("# Camera Parameters (Computed)", file=f)
    print("Camera.type: \"PinHole\"\n", file=f)
    print(f"Camera.fx: {_fmt_scalar_float_10(fx)}", file=f)
    print(f"Camera.fy: {_fmt_scalar_float_10(fy)}", file=f)
    print(f"Camera.cx: {_fmt_scalar_float_10(cx)}", file=f)
    print(f"Camera.cy: {_fmt_scalar_float_10(cy)}\n", file=f)
    print("Camera.k1: 0.0", file=f)
    print("Camera.k2: 0.0", file=f)
    print("Camera.p1: 0.0", file=f)
    print("Camera.p2: 0.0", file=f)
    print("Camera.bFishEye: 0\n", file=f)
    print(f"Camera.width: {int(width)}", file=f)
    print(f"Camera.height: {int(height)}\n", file=f)
    print("Camera.fps: 15.0\n", file=f)
    print(f"Camera.bf: {_fmt_scalar_float_10(bf)}\n", file=f)
    print("Camera.RGB: 1\n", file=f)
    print("ThDepth: 35.0\n", file=f)
    
    print("# Stereo Rectification (Computed)", file=f)
    print(f"LEFT.height: {int(height)}", file=f)
    print(f"LEFT.width: {int(width)}", file=f)
    _print_opencv_matrix(f, "LEFT.D", D1.reshape(1, -1))
    _print_opencv_matrix(f, "LEFT.K", K1)
    _print_opencv_matrix(f, "LEFT.R", R1)
    _print_opencv_matrix(f, "LEFT.P", P1, use_p_style=True)
    print("", file=f)
    print(f"RIGHT.height: {int(height)}", file=f)
    print(f"RIGHT.width: {int(width)}", file=f)
    _print_opencv_matrix(f, "RIGHT.D", D2.reshape(1, -1))
    _print_opencv_matrix(f, "RIGHT.K", K2)
    _print_opencv_matrix(f, "RIGHT.R", R2)
    _print_opencv_matrix(f, "RIGHT.P", P2_corr, use_p_style=True)
    print("", file=f)
    
    print("# ORB Parameters", file=f)
    print("ORBextractor.nFeatures: 1200", file=f)
    print("ORBextractor.scaleFactor: 1.2", file=f)
    print("ORBextractor.nLevels: 8", file=f)
    print("ORBextractor.iniThFAST: 20", file=f)
    print("ORBextractor.minThFAST: 7\n", file=f)
    
    print("# Viewer Parameters", file=f)
    print("Viewer.KeyFrameSize: 0.05", file=f)
    print("Viewer.KeyFrameLineWidth: 1", file=f)
    print("Viewer.GraphLineWidth: 0.9", file=f)
    print("Viewer.PointSize: 2", file=f)
    print("Viewer.CameraSize: 0.08", file=f)
    print("Viewer.CameraLineWidth: 3", file=f)
    print("Viewer.ViewpointX: 0", file=f)
    print("Viewer.ViewpointY: -0.7", file=f)
    print("Viewer.ViewpointZ: -1.8", file=f)
    print("Viewer.ViewpointF: 500", file=f)
    print("Viewer.imageViewScale: 1", file=f)

print(f"{GREEN}[SUCCESS]{RESET} 图像校正和YAML生成完成！")
EOF

# 替换Python脚本中的路径变量
sed -i "s|\$FILTERED_LEFT|$FILTERED_LEFT|g" "$OUTPUT_DIR/$PYTHON_SCRIPT_NAME"
sed -i "s|\$FILTERED_RIGHT|$FILTERED_RIGHT|g" "$OUTPUT_DIR/$PYTHON_SCRIPT_NAME"
sed -i "s|\$OUTPUT_DIR|$OUTPUT_DIR|g" "$OUTPUT_DIR/$PYTHON_SCRIPT_NAME"

# 运行Python脚本
cd "$OUTPUT_DIR"
python3 "$PYTHON_SCRIPT_NAME" >> "$LOG_FILE" 2>&1
if [ ! -f "$OUTPUT_DIR/camera_params.yaml" ]; then
    log_error "YAML文件生成失败，请查阅日志记录。"
    exit 1
fi

# 从 Python 输出的临时文件中提取基线数值
BASELINE_M="N/A"
if [ -f "$OUTPUT_DIR/baseline_val.txt" ]; then
    BASELINE_M=$(cat "$OUTPUT_DIR/baseline_val.txt")
fi

echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
echo -e "${BOLD}${GREEN}              🎉 PIPELINE RUN COMPLETED               ${RESET}"
echo -e "${BOLD}${GREEN}======================================================${RESET}"
echo -e " 📍 ${BOLD}归档总目录:${RESET} $OUTPUT_DIR"
echo -e " 📏 ${BOLD}物理基线(B):${RESET} ${BASELINE_M} 米 (bf / fx)"
echo -e " 📁 ${BOLD}原始帧抽样:${RESET} filtered_left/ & filtered_right/"
echo -e " 📁 ${BOLD}矫正后图像:${RESET} rectified_left/ & rectified_right/"
echo -e " 🧮 ${BOLD}标定元数据:${RESET} stereoParams_optimized.mat"
echo -e " ⚙️  ${BOLD}SLAM 配置 :${RESET} camera_params.yaml"
echo -e " 📜 ${BOLD}运行期日志:${RESET} calibration.log, filtering.log"
echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
