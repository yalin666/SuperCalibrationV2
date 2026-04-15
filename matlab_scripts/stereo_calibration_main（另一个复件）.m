function stereo_calibration_iterative(leftFolder, rightFolder, squareSize, outputFolder, varargin)
    % 迭代式双目相机标定 - 基于误差自动筛选和精确标定
    
    % 解析可选参数
    p = inputParser;
    addOptional(p, 'MaxIterations', 5, @isnumeric);
    addOptional(p, 'ErrorThreshold', 1.5, @isnumeric);  % 误差阈值系数
    addOptional(p, 'MinImages', 40, @isnumeric);  % 最少保留图像数
    addOptional(p, 'TargetError', 0.1, @isnumeric);  % 目标误差
    parse(p, varargin{:});
    
    maxIterations = p.Results.MaxIterations;
    errorThresholdFactor = p.Results.ErrorThreshold;
    minImages = p.Results.MinImages;
    targetError = p.Results.TargetError;
    
    % 输入参数类型转换
    if ischar(squareSize)
        squareSize = str2double(squareSize);
    end
    
    fprintf('========== 开始迭代式双目相机标定 ==========\n');
    fprintf('配置参数:\n');
    fprintf('  最大迭代次数: %d\n', maxIterations);
    fprintf('  误差阈值系数: %.2f\n', errorThresholdFactor);
    fprintf('  最少图像数: %d\n', minImages);
    fprintf('  目标误差: %.3f 像素\n', targetError);
    fprintf('==========================================\n\n');
    
    % 初始化
    leftImages = dir(fullfile(leftFolder, '*.jpg'));
    if isempty(leftImages)
        leftImages = dir(fullfile(leftFolder, '*.png'));
    end
    
    rightImages = dir(fullfile(rightFolder, '*.jpg'));
    if isempty(rightImages)
        rightImages = dir(fullfile(rightFolder, '*.png'));
    end
    
    % 创建初始图像列表
    activeLeftImages = fullfile(leftFolder, {leftImages.name});
    activeRightImages = fullfile(rightFolder, {rightImages.name});
    
    % 记录每次迭代的结果
    iterationResults = [];
    removedImages = {};
    
    % 迭代标定
    for iter = 1:maxIterations
        fprintf('\n========== 迭代 %d/%d ==========\n', iter, maxIterations);
        fprintf('当前图像数: %d\n', length(activeLeftImages));
        
        % 执行标定
        [stereoParams, frameErrors, errorStats, imagesUsed] = ...
            performCalibration(activeLeftImages, activeRightImages, squareSize);
        
        % 记录结果
        result = struct();
        result.iteration = iter;
        result.numImages = sum(imagesUsed);
        result.meanError = errorStats.meanError;
        result.stdError = errorStats.stdError;
        result.minError = errorStats.minError;
        result.maxError = errorStats.maxError;
        iterationResults = [iterationResults, result];
        
        fprintf('\n迭代 %d 结果:\n', iter);
        fprintf('  使用图像数: %d\n', result.numImages);
        fprintf('  平均误差: %.3f 像素\n', result.meanError);
        fprintf('  标准差: %.3f 像素\n', result.stdError);
        fprintf('  误差范围: [%.3f, %.3f]\n', result.minError, result.maxError);
        
        % 检查是否达到目标
        if result.meanError <= targetError
            fprintf('\n✓ 达到目标误差! (%.3f <= %.3f)\n', result.meanError, targetError);
            break;
        end
        
        % 筛选图像
        [activeLeftImages, activeRightImages, removedThisIter] = ...
            filterImages(activeLeftImages, activeRightImages, frameErrors, ...
                        errorStats, errorThresholdFactor, minImages, imagesUsed);
        
        removedImages = [removedImages, removedThisIter];
        
        % 检查是否需要继续
        if isempty(removedThisIter)
            fprintf('\n没有需要剔除的图像，停止迭代\n');
            break;
        end
        
        if length(activeLeftImages) <= minImages
            fprintf('\n警告: 达到最少图像数限制，停止迭代\n');
            break;
        end
    end
    
    % 最终标定
    fprintf('\n========== 执行最终标定 ==========\n');
    [finalStereoParams, finalFrameErrors, finalErrorStats, finalImagesUsed] = ...
        performCalibration(activeLeftImages, activeRightImages, squareSize);
    
    % 保存结果
    saveIterativeResults(outputFolder, finalStereoParams, finalFrameErrors, ...
                        finalErrorStats, iterationResults, removedImages, ...
                        activeLeftImages, activeRightImages);
    
    % 生成迭代报告
    generateIterativeReport(outputFolder, iterationResults, finalErrorStats);
    
    fprintf('\n========== 迭代标定完成! ==========\n');
    fprintf('最终结果:\n');
    fprintf('  使用图像: %d/%d\n', length(activeLeftImages), length(leftImages));
    fprintf('  平均误差: %.3f 像素\n', finalErrorStats.meanError);
    fprintf('  误差改善: %.1f%%\n', ...
        (iterationResults(1).meanError - finalErrorStats.meanError) / iterationResults(1).meanError * 100);
end

function [stereoParams, frameErrors, errorStats, imagesUsed] = ...
    performCalibration(leftImageFiles, rightImageFiles, squareSize)
    % 执行一次标定
    
    % 检测棋盘格
    [imagePoints, boardSize, imagesUsed] = detectCheckerboardPoints(...
        leftImageFiles, rightImageFiles);
    
    % 生成世界坐标
    worldPoints = generateCheckerboardPoints(boardSize, squareSize);
    
    % 读取图像尺寸
    I = imread(leftImageFiles{1});
    imageSize = [size(I, 1), size(I, 2)];
    
    % 执行标定
    [stereoParams, pairsUsed, estimationErrors] = estimateCameraParameters(...
        imagePoints, worldPoints, ...
        'ImageSize', imageSize, ...
        'NumRadialDistortionCoefficients', 3, ...
        'EstimateTangentialDistortion', true, ...
        'EstimateSkew', false);
    
    % 提取每帧误差
    [frameErrors, errorStats] = extractFrameErrors(stereoParams, imagesUsed, leftImageFiles);
end

function [frameErrors, errorStats] = extractFrameErrors(stereoParams, imagesUsed, imageFiles)
    % 提取每帧的重投影误差
    
    usedIndices = find(imagesUsed);
    numUsed = sum(imagesUsed);
    
    frameErrors = struct();
    frameErrors.frameIndex = usedIndices;
    frameErrors.imageName = cellfun(@(x) getFileName(x), imageFiles(usedIndices), 'UniformOutput', false);
    
    % 获取重投影误差
    if isprop(stereoParams.CameraParameters1, 'ReprojectionErrors')
        leftReprojErrors = stereoParams.CameraParameters1.ReprojectionErrors;
        rightReprojErrors = stereoParams.CameraParameters2.ReprojectionErrors;
        
        frameErrors.leftError = zeros(numUsed, 1);
        frameErrors.rightError = zeros(numUsed, 1);
        frameErrors.meanError = zeros(numUsed, 1);
        
        for i = 1:numUsed
            leftPointErrors = leftReprojErrors(:,:,i);
            rightPointErrors = rightReprojErrors(:,:,i);
            
            frameErrors.leftError(i) = sqrt(mean(leftPointErrors(:).^2));
            frameErrors.rightError(i) = sqrt(mean(rightPointErrors(:).^2));
            frameErrors.meanError(i) = (frameErrors.leftError(i) + frameErrors.rightError(i)) / 2;
        end
    else
        % 使用总体误差的估计
        meanError = stereoParams.MeanReprojectionError;
        frameErrors.leftError = meanError * ones(numUsed, 1);
        frameErrors.rightError = meanError * ones(numUsed, 1);
        frameErrors.meanError = meanError * ones(numUsed, 1);
    end
    
    % 计算统计信息
    errorStats = computeErrorStats(frameErrors);
end

function errorStats = computeErrorStats(frameErrors)
    % 计算误差统计信息
    errorStats = struct();
    errorStats.meanError = mean(frameErrors.meanError);
    errorStats.stdError = std(frameErrors.meanError);
    errorStats.minError = min(frameErrors.meanError);
    errorStats.maxError = max(frameErrors.meanError);
    errorStats.medianError = median(frameErrors.meanError);
    
    % 计算不同阈值
    errorStats.threshold_1sigma = errorStats.meanError + errorStats.stdError;
    errorStats.threshold_15sigma = errorStats.meanError + 1.5 * errorStats.stdError;
    errorStats.threshold_2sigma = errorStats.meanError + 2 * errorStats.stdError;
    errorStats.threshold_quartile = prctile(frameErrors.meanError, 75);
end

function [newLeftImages, newRightImages, removedImages] = ...
    filterImages(leftImages, rightImages, frameErrors, errorStats, ...
                thresholdFactor, minImages, imagesUsed)
    % 基于误差筛选图像
    
    % 计算阈值
    threshold = errorStats.meanError + thresholdFactor * errorStats.stdError;
    
    % 找出高误差图像
    highErrorMask = frameErrors.meanError > threshold;
    
    % 确保保留足够数量的图像
    numToRemove = sum(highErrorMask);
    numRemaining = length(leftImages) - numToRemove;
    
    if numRemaining < minImages
        % 只移除误差最大的图像
        [~, sortIdx] = sort(frameErrors.meanError, 'descend');
        numCanRemove = length(leftImages) - minImages;
        if numCanRemove > 0
            removeIndices = sortIdx(1:numCanRemove);
            highErrorMask = false(size(frameErrors.meanError));
            highErrorMask(removeIndices) = true;
        else
            highErrorMask = false(size(frameErrors.meanError));
        end
    end
    
    % 移除高误差图像
    removedImages = {};
    keepMask = true(size(leftImages));
    
    if any(highErrorMask)
        usedIndices = find(imagesUsed);
        removeGlobalIndices = usedIndices(highErrorMask);
        keepMask(removeGlobalIndices) = false;
        
        removedImages = leftImages(removeGlobalIndices);
        
        fprintf('\n剔除 %d 张高误差图像 (阈值: %.3f):\n', sum(~keepMask), threshold);
        for i = 1:min(5, length(removedImages))
            [~, name] = fileparts(removedImages{i});
            idx = find(strcmp(frameErrors.imageName, [name, '.jpg']) | ...
                      strcmp(frameErrors.imageName, [name, '.png']));
            if ~isempty(idx)
                fprintf('  - %s (误差: %.3f)\n', frameErrors.imageName{idx}, ...
                       frameErrors.meanError(idx));
            end
        end
        if length(removedImages) > 5
            fprintf('  ... 还有 %d 张\n', length(removedImages) - 5);
        end
    end
    
    newLeftImages = leftImages(keepMask);
    newRightImages = rightImages(keepMask);
end

function name = getFileName(fullPath)
    % 从完整路径获取文件名
    [~, name, ext] = fileparts(fullPath);
    name = [name, ext];
end

function generateIterativeReport(outputFolder, iterationResults, finalErrorStats)
    % 生成迭代报告图
    
    figure('Position', [100, 100, 1200, 800], 'Visible', 'off');
    
    % 子图1: 误差变化曲线
    subplot(2, 2, 1);
    iterations = [iterationResults.iteration];
    meanErrors = [iterationResults.meanError];
    stdErrors = [iterationResults.stdError];
    
    errorbar(iterations, meanErrors, stdErrors, 'b-o', 'LineWidth', 2);
    hold on;
    plot(iterations, meanErrors, 'r--', 'LineWidth', 1.5);
    xlabel('迭代次数');
    ylabel('平均重投影误差 (像素)');
    title('误差随迭代变化');
    grid on;
    
    % 子图2: 图像数量变化
    subplot(2, 2, 2);
    numImages = [iterationResults.numImages];
    bar(iterations, numImages, 'FaceColor', [0.3, 0.6, 0.9]);
    xlabel('迭代次数');
    ylabel('使用的图像数');
    title('图像数量变化');
    grid on;
    
    % 子图3: 误差改善率
    subplot(2, 2, 3);
    improvementRate = zeros(1, length(iterations)-1);
    for i = 2:length(iterations)
        improvementRate(i-1) = (meanErrors(i-1) - meanErrors(i)) / meanErrors(i-1) * 100;
    end
    if ~isempty(improvementRate)
        bar(iterations(2:end), improvementRate, 'FaceColor', [0.9, 0.6, 0.3]);
        xlabel('迭代次数');
        ylabel('误差改善率 (%)');
        title('每次迭代的改善');
        grid on;
    end
    
    % 子图4: 统计信息
    subplot(2, 2, 4);
    text(0.1, 0.9, '最终标定结果:', 'FontSize', 14, 'FontWeight', 'bold');
    text(0.1, 0.8, sprintf('平均误差: %.3f 像素', finalErrorStats.meanError), 'FontSize', 12);
    text(0.1, 0.7, sprintf('标准差: %.3f 像素', finalErrorStats.stdError), 'FontSize', 12);
    text(0.1, 0.6, sprintf('最小误差: %.3f 像素', finalErrorStats.minError), 'FontSize', 12);
    text(0.1, 0.5, sprintf('最大误差: %.3f 像素', finalErrorStats.maxError), 'FontSize', 12);
    text(0.1, 0.3, sprintf('总体改善: %.1f%%', ...
        (iterationResults(1).meanError - finalErrorStats.meanError) / iterationResults(1).meanError * 100), ...
        'FontSize', 12, 'Color', 'blue');
    axis off;
    
    % 保存图表
    saveas(gcf, fullfile(outputFolder, 'iterative_calibration_report.png'));
    close(gcf);
end

function saveIterativeResults(outputFolder, stereoParams, frameErrors, errorStats, ...
                             iterationResults, removedImages, activeLeftImages, activeRightImages)
    % 保存迭代标定结果
    
    % 保存MATLAB格式
    save(fullfile(outputFolder, 'stereoParams_iterative.mat'), ...
         'stereoParams', 'frameErrors', 'errorStats', ...
         'iterationResults', 'removedImages', 'activeLeftImages', 'activeRightImages');
    
    % 保存迭代日志
    fid = fopen(fullfile(outputFolder, 'iterative_log.txt'), 'w');
    fprintf(fid, '========== 迭代标定日志 ==========\n\n');
    fprintf(fid, '生成时间: %s\n\n', datestr(now));
    
    fprintf(fid, '标定配置:\n');
    fprintf(fid, '  初始图像数: %d\n', iterationResults(1).numImages);
    fprintf(fid, '  最终图像数: %d\n', length(activeLeftImages));
    fprintf(fid, '  剔除图像数: %d\n', length(removedImages));
    fprintf(fid, '  总迭代次数: %d\n\n', length(iterationResults));
    
    for i = 1:length(iterationResults)
        fprintf(fid, '迭代 %d:\n', iterationResults(i).iteration);
        fprintf(fid, '  图像数: %d\n', iterationResults(i).numImages);
        fprintf(fid, '  平均误差: %.3f\n', iterationResults(i).meanError);
        fprintf(fid, '  标准差: %.3f\n', iterationResults(i).stdError);
        fprintf(fid, '\n');
    end
    
    fprintf(fid, '\n剔除的图像列表:\n');
    for i = 1:length(removedImages)
        [~, name, ext] = fileparts(removedImages{i});
        fprintf(fid, '  %s%s\n', name, ext);
    end
    
    fprintf(fid, '\n最终保留的图像:\n');
    for i = 1:length(activeLeftImages)
        [~, name, ext] = fileparts(activeLeftImages{i});
        fprintf(fid, '  %s%s\n', name, ext);
    end
    
    fclose(fid);
    
    % 保存最终使用的图像列表
    fid = fopen(fullfile(outputFolder, 'final_images.txt'), 'w');
    for i = 1:length(activeLeftImages)
        fprintf(fid, '%s\n', activeLeftImages{i});
    end
    fclose(fid);
    
    % ===== 新增：保存JSON格式的标定结果 =====
    saveIterativeJSON(outputFolder, stereoParams, errorStats, iterationResults, ...
                     length(activeLeftImages), length(removedImages));
    
    % ===== 新增：保存OpenCV格式 =====
    saveIterativeOpenCV(outputFolder, stereoParams);
end

% ===== 新增的JSON保存函数 =====
function saveIterativeJSON(outputFolder, stereoParams, errorStats, iterationResults, ...
                          finalImageCount, removedCount)
    % 保存JSON格式的迭代标定结果
    
    data = struct();
    
    % 图像尺寸
    data.imageSize = [stereoParams.CameraParameters1.ImageSize(2), ...
                      stereoParams.CameraParameters1.ImageSize(1)];
    
    % 左相机内参
    K1 = stereoParams.CameraParameters1.IntrinsicMatrix';
    data.leftCamera.intrinsicMatrix = K1;
    data.leftCamera.fx = K1(1,1);
    data.leftCamera.fy = K1(2,2);
    data.leftCamera.cx = K1(1,3);
    data.leftCamera.cy = K1(2,3);
    data.leftCamera.radialDistortion = stereoParams.CameraParameters1.RadialDistortion;
    data.leftCamera.tangentialDistortion = stereoParams.CameraParameters1.TangentialDistortion;
    data.leftCamera.k1 = stereoParams.CameraParameters1.RadialDistortion(1);
    data.leftCamera.k2 = stereoParams.CameraParameters1.RadialDistortion(2);
    data.leftCamera.k3 = stereoParams.CameraParameters1.RadialDistortion(3);
    data.leftCamera.p1 = stereoParams.CameraParameters1.TangentialDistortion(1);
    data.leftCamera.p2 = stereoParams.CameraParameters1.TangentialDistortion(2);
    
    % 右相机内参
    K2 = stereoParams.CameraParameters2.IntrinsicMatrix';
    data.rightCamera.intrinsicMatrix = K2;
    data.rightCamera.fx = K2(1,1);
    data.rightCamera.fy = K2(2,2);
    data.rightCamera.cx = K2(1,3);
    data.rightCamera.cy = K2(2,3);
    data.rightCamera.radialDistortion = stereoParams.CameraParameters2.RadialDistortion;
    data.rightCamera.tangentialDistortion = stereoParams.CameraParameters2.TangentialDistortion;
    data.rightCamera.k1 = stereoParams.CameraParameters2.RadialDistortion(1);
    data.rightCamera.k2 = stereoParams.CameraParameters2.RadialDistortion(2);
    data.rightCamera.k3 = stereoParams.CameraParameters2.RadialDistortion(3);
    data.rightCamera.p1 = stereoParams.CameraParameters2.TangentialDistortion(1);
    data.rightCamera.p2 = stereoParams.CameraParameters2.TangentialDistortion(2);
    
    % 双目外参
    data.stereo.rotationMatrix = stereoParams.RotationOfCamera2;
    data.stereo.translationVector = stereoParams.TranslationOfCamera2;
    data.stereo.baseline = norm(stereoParams.TranslationOfCamera2);
    
    % 基础矩阵和本质矩阵（如果存在）
    if isprop(stereoParams, 'EssentialMatrix')
        data.stereo.essentialMatrix = stereoParams.EssentialMatrix;
    end
    if isprop(stereoParams, 'FundamentalMatrix')
        data.stereo.fundamentalMatrix = stereoParams.FundamentalMatrix;
    end
    
    % 误差信息
    data.errors.final.mean = errorStats.meanError;
    data.errors.final.std = errorStats.stdError;
    data.errors.final.min = errorStats.minError;
    data.errors.final.max = errorStats.maxError;
    data.errors.final.median = errorStats.medianError;
    
    % 迭代信息
    data.iterative.totalIterations = length(iterationResults);
    data.iterative.initialImageCount = iterationResults(1).numImages;
    data.iterative.finalImageCount = finalImageCount;
    data.iterative.removedImageCount = removedCount;
    data.iterative.initialError = iterationResults(1).meanError;
    data.iterative.finalError = errorStats.meanError;
    data.iterative.improvementPercent = (iterationResults(1).meanError - errorStats.meanError) / ...
                                        iterationResults(1).meanError * 100;
    
    % 每次迭代的历史记录
    data.iterative.history = iterationResults;
    
    % 写入JSON文件
    jsonStr = jsonencode(data);
    jsonStr = prettifyJSON(jsonStr);
    
    fid = fopen(fullfile(outputFolder, 'calibration_iterative.json'), 'w');
    fprintf(fid, '%s', jsonStr);
    fclose(fid);
    
    fprintf('已保存JSON格式标定结果: calibration_iterative.json\n');
end

% ===== JSON美化函数 =====
function prettyJSON = prettifyJSON(jsonStr)
    % 简单的JSON美化，添加缩进和换行
    prettyJSON = jsonStr;
    
    % 替换标记以添加换行
    prettyJSON = strrep(prettyJSON, ',', sprintf(',\n'));
    prettyJSON = strrep(prettyJSON, '{', sprintf('{\n'));
    prettyJSON = strrep(prettyJSON, '}', sprintf('\n}'));
    prettyJSON = strrep(prettyJSON, '[', sprintf('[\n'));
    prettyJSON = strrep(prettyJSON, ']', sprintf('\n]'));
    
    % 处理特殊情况，避免过度换行
    prettyJSON = regexprep(prettyJSON, '\n\s*\n', '\n');
end

% ===== 新增：保存OpenCV YAML格式 =====
function saveIterativeOpenCV(outputFolder, stereoParams)
    % 保存为OpenCV兼容的YAML格式
    
    filename = fullfile(outputFolder, 'calibration_iterative_opencv.yml');
    fid = fopen(filename, 'w');
    
    fprintf(fid, '%%YAML:1.0\n');
    fprintf(fid, '---\n');
    
    % 图像尺寸
    fprintf(fid, 'imageWidth: %d\n', stereoParams.CameraParameters1.ImageSize(2));
    fprintf(fid, 'imageHeight: %d\n', stereoParams.CameraParameters1.ImageSize(1));
    
    % 左相机内参
    K1 = stereoParams.CameraParameters1.IntrinsicMatrix';
    fprintf(fid, 'K1: !!opencv-matrix\n');
    fprintf(fid, '   rows: 3\n');
    fprintf(fid, '   cols: 3\n');
    fprintf(fid, '   dt: d\n');
    fprintf(fid, '   data: [%.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f]\n', ...
        K1(1,1), K1(1,2), K1(1,3), K1(2,1), K1(2,2), K1(2,3), K1(3,1), K1(3,2), K1(3,3));
    
    % 左相机畸变系数
    D1 = [stereoParams.CameraParameters1.RadialDistortion, ...
          stereoParams.CameraParameters1.TangentialDistortion];
    fprintf(fid, 'D1: !!opencv-matrix\n');
    fprintf(fid, '   rows: 1\n');
    fprintf(fid, '   cols: 5\n');
    fprintf(fid, '   dt: d\n');
    fprintf(fid, '   data: [%.8f, %.8f, %.8f, %.8f, %.8f]\n', D1);
    
    % 右相机内参
    K2 = stereoParams.CameraParameters2.IntrinsicMatrix';
    fprintf(fid, 'K2: !!opencv-matrix\n');
    fprintf(fid, '   rows: 3\n');
    fprintf(fid, '   cols: 3\n');
    fprintf(fid, '   dt: d\n');
    fprintf(fid, '   data: [%.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f]\n', ...
        K2(1,1), K2(1,2), K2(1,3), K2(2,1), K2(2,2), K2(2,3), K2(3,1), K2(3,2), K2(3,3));
    
    % 右相机畸变系数
    D2 = [stereoParams.CameraParameters2.RadialDistortion, ...
          stereoParams.CameraParameters2.TangentialDistortion];
    fprintf(fid, 'D2: !!opencv-matrix\n');
    fprintf(fid, '   rows: 1\n');
    fprintf(fid, '   cols: 5\n');
    fprintf(fid, '   dt: d\n');
    fprintf(fid, '   data: [%.8f, %.8f, %.8f, %.8f, %.8f]\n', D2);
    
    % 旋转矩阵
    R = stereoParams.RotationOfCamera2;
    fprintf(fid, 'R: !!opencv-matrix\n');
    fprintf(fid, '   rows: 3\n');
    fprintf(fid, '   cols: 3\n');
    fprintf(fid, '   dt: d\n');
    fprintf(fid, '   data: [%.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f, %.8f]\n', ...
        R(1,1), R(1,2), R(1,3), R(2,1), R(2,2), R(2,3), R(3,1), R(3,2), R(3,3));
    
    % 平移向量
    T = stereoParams.TranslationOfCamera2;
    fprintf(fid, 'T: !!opencv-matrix\n');
    fprintf(fid, '   rows: 3\n');
    fprintf(fid, '   cols: 1\n');
    fprintf(fid, '   dt: d\n');
    fprintf(fid, '   data: [%.8f, %.8f, %.8f]\n', T);
    
    % 基线和重投影误差
    fprintf(fid, 'baseline: %.8f\n', norm(T));
    fprintf(fid, 'meanReprojectionError: %.8f\n', stereoParams.MeanReprojectionError);
    
    fclose(fid);
    
    fprintf('已保存OpenCV格式标定结果: calibration_iterative_opencv.yml\n');
end
