function analyze_calibration_errors(stereoParamsFile, leftFolder, rightFolder, outputFolder)
    % 分析已有标定结果的每帧误差
    
    fprintf('========== 分析标定误差 ==========\n');
    
    % 加载标定结果
    if ischar(stereoParamsFile)
        load(stereoParamsFile, 'stereoParams', 'imagesUsed');
    else
        stereoParams = stereoParamsFile;
    end
    
    % 获取图像文件列表
    leftImages = dir(fullfile(leftFolder, '*.jpg'));
    if isempty(leftImages)
        leftImages = dir(fullfile(leftFolder, '*.png'));
    end
    
    rightImages = dir(fullfile(rightFolder, '*.jpg'));
    if isempty(rightImages)
        rightImages = dir(fullfile(rightFolder, '*.png'));
    end
    
    % 创建文件路径
    leftImageFiles = fullfile(leftFolder, {leftImages.name});
    rightImageFiles = fullfile(rightFolder, {rightImages.name});
    
    % 重新检测棋盘格角点
    fprintf('重新检测棋盘格角点...\n');
    [imagePoints, boardSize] = detectCheckerboardPoints(leftImageFiles, rightImageFiles);
    
    % 生成世界坐标点
    squareSize = 30; % 使用您的实际方格大小
    worldPoints = generateCheckerboardPoints(boardSize, squareSize);
    
    % 计算每个视图的重投影误差
    fprintf('计算每帧重投影误差...\n');
    numUsedImages = sum(imagesUsed);
    frameErrors = struct();
    frameErrors.frameIndex = [];
    frameErrors.imageName = {};
    frameErrors.leftError = [];
    frameErrors.rightError = [];
    frameErrors.meanError = [];
    
    % 遍历所有使用的图像
    usedIdx = 0;
    for i = 1:length(imagesUsed)
        if imagesUsed(i)
            usedIdx = usedIdx + 1;
            
            try
                % 获取当前帧的图像点
                imagePointsLeft = squeeze(imagePoints(:,:,1,i));
                imagePointsRight = squeeze(imagePoints(:,:,2,i));
                
                % 计算左相机重投影误差
                % 使用相机参数中存储的旋转和平移
                R1 = stereoParams.CameraParameters1.RotationMatrices(:,:,usedIdx);
                t1 = stereoParams.CameraParameters1.TranslationVectors(usedIdx,:);
                
                % 将世界点转换到相机坐标系
                worldPointsHomogeneous = [worldPoints, ones(size(worldPoints,1), 1)];
                
                % 左相机投影
                RT1 = [R1; t1];
                cameraPoints1 = worldPointsHomogeneous * RT1';
                projectedPoints1 = cameraPoints1(:,1:2) ./ cameraPoints1(:,3);
                
                % 应用畸变模型
                projectedPoints1_distorted = applyDistortion(projectedPoints1, stereoParams.CameraParameters1);
                
                % 投影到图像平面
                K1 = stereoParams.CameraParameters1.IntrinsicMatrix';
                projectedImagePoints1 = projectedPoints1_distorted * K1(1:2,1:2)' + K1(1:2,3)';
                
                % 计算左相机误差
                leftError = mean(sqrt(sum((imagePointsLeft - projectedImagePoints1).^2, 2)));
                
                % 右相机投影
                % 右相机的旋转和平移是相对于左相机的
                R2 = R1 * stereoParams.RotationOfCamera2;
                t2 = (R1 * stereoParams.TranslationOfCamera2')' + t1;
                
                RT2 = [R2; t2];
                cameraPoints2 = worldPointsHomogeneous * RT2';
                projectedPoints2 = cameraPoints2(:,1:2) ./ cameraPoints2(:,3);
                
                % 应用畸变模型
                projectedPoints2_distorted = applyDistortion(projectedPoints2, stereoParams.CameraParameters2);
                
                % 投影到图像平面
                K2 = stereoParams.CameraParameters2.IntrinsicMatrix';
                projectedImagePoints2 = projectedPoints2_distorted * K2(1:2,1:2)' + K2(1:2,3)';
                
                % 计算右相机误差
                rightError = mean(sqrt(sum((imagePointsRight - projectedImagePoints2).^2, 2)));
                
                % 记录结果
                frameErrors.frameIndex(end+1) = i;
                frameErrors.imageName{end+1} = leftImages(i).name;
                frameErrors.leftError(end+1) = leftError;
                frameErrors.rightError(end+1) = rightError;
                frameErrors.meanError(end+1) = (leftError + rightError) / 2;
                
                fprintf('  图像 %s: 左=%.3f, 右=%.3f, 平均=%.3f 像素\n', ...
                    leftImages(i).name, leftError, rightError, (leftError + rightError) / 2);
                
            catch ME
                fprintf('  图像 %s: 计算错误 - %s\n', leftImages(i).name, ME.message);
                % 使用默认值
                frameErrors.frameIndex(end+1) = i;
                frameErrors.imageName{end+1} = leftImages(i).name;
                frameErrors.leftError(end+1) = NaN;
                frameErrors.rightError(end+1) = NaN;
                frameErrors.meanError(end+1) = NaN;
            end
        end
    end
    
    % 移除NaN值
    validIdx = ~isnan(frameErrors.meanError);
    frameErrors.frameIndex = frameErrors.frameIndex(validIdx);
    frameErrors.imageName = frameErrors.imageName(validIdx);
    frameErrors.leftError = frameErrors.leftError(validIdx);
    frameErrors.rightError = frameErrors.rightError(validIdx);
    frameErrors.meanError = frameErrors.meanError(validIdx);
    
    if isempty(frameErrors.meanError)
        fprintf('错误：无法计算任何帧的误差\n');
        return;
    end
    
    % 统计分析
    fprintf('\n误差统计:\n');
    fprintf('  有效帧数: %d / %d\n', length(frameErrors.meanError), numUsedImages);
    fprintf('  平均重投影误差: %.3f 像素\n', mean(frameErrors.meanError));
    fprintf('  误差标准差: %.3f 像素\n', std(frameErrors.meanError));
    fprintf('  最小误差: %.3f 像素\n', min(frameErrors.meanError));
    fprintf('  最大误差: %.3f 像素\n', max(frameErrors.meanError));
    
    % 识别高误差帧
    threshold = mean(frameErrors.meanError) + 2 * std(frameErrors.meanError);
    highErrorIdx = frameErrors.meanError > threshold;
    
    fprintf('\n高误差帧 (> %.3f 像素):\n', threshold);
    if any(highErrorIdx)
        highErrorFrames = frameErrors.imageName(highErrorIdx);
        highErrorValues = frameErrors.meanError(highErrorIdx);
        [sortedValues, sortIdx] = sort(highErrorValues, 'descend');
        for i = 1:length(sortIdx)
            fprintf('  %s: %.3f 像素\n', highErrorFrames{sortIdx(i)}, sortedValues(i));
        end
    else
        fprintf('  无\n');
    end
    
    % 保存详细的CSV报告
    csvFile = fullfile(outputFolder, 'detailed_error_analysis.csv');
    saveDetailedErrorReport(frameErrors, threshold, csvFile);
    fprintf('\n详细误差报告已保存到: %s\n', csvFile);
    
    % 生成误差分析图表
    plotFile = fullfile(outputFolder, 'error_analysis_detailed.png');
    generateDetailedErrorPlot(frameErrors, threshold, plotFile);
    fprintf('误差分析图表已保存到: %s\n', plotFile);
    
    % 生成筛选建议
    suggestFile = fullfile(outputFolder, 'image_selection_suggestions.txt');
    generateSelectionSuggestions(frameErrors, threshold, suggestFile);
    fprintf('图像筛选建议已保存到: %s\n', suggestFile);
end

function distortedPoints = applyDistortion(undistortedPoints, cameraParams)
    % 应用镜头畸变模型
    x = undistortedPoints(:,1);
    y = undistortedPoints(:,2);
    
    r2 = x.^2 + y.^2;
    r4 = r2.^2;
    r6 = r2.^3;
    
    % 径向畸变
    k = cameraParams.RadialDistortion;
    if length(k) < 3
        k(3) = 0;
    end
    radialFactor = 1 + k(1)*r2 + k(2)*r4 + k(3)*r6;
    
    % 切向畸变
    p = cameraParams.TangentialDistortion;
    if length(p) < 2
        p = [0, 0];
    end
    
    xDistorted = x.*radialFactor + 2*p(1)*x.*y + p(2)*(r2 + 2*x.^2);
    yDistorted = y.*radialFactor + p(1)*(r2 + 2*y.^2) + 2*p(2)*x.*y;
    
    distortedPoints = [xDistorted, yDistorted];
end

function saveDetailedErrorReport(frameErrors, threshold, filename)
    % 保存详细的误差报告
    fid = fopen(filename, 'w');
    
    % 写入表头
    fprintf(fid, '帧索引,图像名称,左相机误差(像素),右相机误差(像素),平均误差(像素),状态,建议\n');
    
    % 按误差排序
    [sortedErrors, sortIdx] = sort(frameErrors.meanError, 'descend');
    
    % 写入数据
    for i = 1:length(sortedErrors)
        idx = sortIdx(i);
        frameIdx = frameErrors.frameIndex(idx);
        imageName = frameErrors.imageName{idx};
        leftErr = frameErrors.leftError(idx);
        rightErr = frameErrors.rightError(idx);
        meanErr = frameErrors.meanError(idx);
        
        % 判断状态和建议
        if meanErr > threshold
            status = '高误差';
            suggestion = '建议剔除';
        elseif meanErr > mean(frameErrors.meanError) + std(frameErrors.meanError)
            status = '偏高';
            suggestion = '考虑剔除';
        elseif meanErr < mean(frameErrors.meanError) - std(frameErrors.meanError)
            status = '良好';
            suggestion = '保留';
        else
            status = '正常';
            suggestion = '保留';
        end
        
        fprintf(fid, '%d,%s,%.4f,%.4f,%.4f,%s,%s\n', ...
            frameIdx, imageName, leftErr, rightErr, meanErr, status, suggestion);
    end
    
    % 写入统计信息
    fprintf(fid, '\n\n误差统计:\n');
    fprintf(fid, '指标,值\n');
    fprintf(fid, '平均误差,%.4f\n', mean(frameErrors.meanError));
    fprintf(fid, '标准差,%.4f\n', std(frameErrors.meanError));
    fprintf(fid, '最小误差,%.4f\n', min(frameErrors.meanError));
    fprintf(fid, '最大误差,%.4f\n', max(frameErrors.meanError));
    fprintf(fid, '阈值,%.4f\n', threshold);
    fprintf(fid, '高误差帧数,%d\n', sum(frameErrors.meanError > threshold));
    fprintf(fid, '总帧数,%d\n', length(frameErrors.meanError));
    
    fclose(fid);
end

function generateDetailedErrorPlot(frameErrors, threshold, filename)
    % 生成详细的误差分析图表
    figure('Visible', 'off', 'Position', [100, 100, 1600, 1000]);
    
    % 子图1: 每帧误差条形图（按误差排序）
    subplot(2,3,1);
    [sortedErrors, ~] = sort(frameErrors.meanError, 'descend');
    bar(sortedErrors);
    hold on;
    yline(mean(frameErrors.meanError), 'g--', 'LineWidth', 2);
    yline(threshold, 'r--', 'LineWidth', 2);
    xlabel('图像索引（按误差排序）');
    ylabel('重投影误差 (像素)');
    title('误差分布（降序排列）');
    legend('帧误差', '平均误差', '剔除阈值', 'Location', 'best');
    grid on;
    
    % 子图2: 左右相机误差对比
    subplot(2,3,2);
    scatter(frameErrors.leftError, frameErrors.rightError, 50, frameErrors.meanError, 'filled');
    colorbar;
    xlabel('左相机误差 (像素)');
    ylabel('右相机误差 (像素)');
    title('左右相机误差相关性');
    hold on;
    maxErr = max([frameErrors.leftError, frameErrors.rightError]);
    plot([0 maxErr], [0 maxErr], 'k--');
    grid on;
    axis equal;
    
    % 子图3: 误差分布直方图
    subplot(2,3,3);
    histogram(frameErrors.meanError, 30, 'FaceColor', 'b');
    hold on;
    xline(mean(frameErrors.meanError), 'g--', 'LineWidth', 2);
    xline(threshold, 'r--', 'LineWidth', 2);
    xlabel('重投影误差 (像素)');
    ylabel('频数');
    title('误差分布直方图');
    legend('误差分布', '平均值', '剔除阈值');
    grid on;
    
    % 子图4: 时序误差图
    subplot(2,3,4);
    plot(frameErrors.frameIndex, frameErrors.meanError, 'b-o');
    hold on;
    yline(mean(frameErrors.meanError), 'g--', 'LineWidth', 2);
    yline(threshold, 'r--', 'LineWidth', 2);
    xlabel('原始图像索引');
    ylabel('重投影误差 (像素)');
    title('按拍摄顺序的误差分布');
    grid on;
    
    % 子图5: 误差统计箱线图
    subplot(2,3,5);
    boxplot([frameErrors.leftError', frameErrors.rightError', frameErrors.meanError'], ...
            {'左相机', '右相机', '平均'});
    ylabel('重投影误差 (像素)');
    title('误差统计箱线图');
    grid on;
    
    % 子图6: 累积误差分布
    subplot(2,3,6);
    sortedForCDF = sort(frameErrors.meanError);
    plot(sortedForCDF, (1:length(sortedForCDF))/length(sortedForCDF), 'b-', 'LineWidth', 2);
    hold on;
    xline(mean(frameErrors.meanError), 'g--', 'LineWidth', 2);
    xline(threshold, 'r--', 'LineWidth', 2);
    xlabel('重投影误差 (像素)');
    ylabel('累积概率');
    title('误差累积分布函数');
    legend('CDF', '平均值', '剔除阈值');
    grid on;
    
    % 总标题
    sgtitle(sprintf('双目标定误差详细分析 (共%d帧)', length(frameErrors.meanError)), ...
            'FontSize', 16, 'FontWeight', 'bold');
    
    % 保存图像
    saveas(gcf, filename);
    close(gcf);
end

function generateSelectionSuggestions(frameErrors, threshold, filename)
    % 生成图像筛选建议
    fid = fopen(filename, 'w');
    
    fprintf(fid, '========== 图像筛选建议 ==========\n\n');
    fprintf(fid, '生成时间: %s\n\n', datestr(now));
    
    fprintf(fid, '1. 误差统计概览\n');
    fprintf(fid, '   - 总图像数: %d\n', length(frameErrors.meanError));
    fprintf(fid, '   - 平均误差: %.3f 像素\n', mean(frameErrors.meanError));
    fprintf(fid, '   - 误差标准差: %.3f 像素\n', std(frameErrors.meanError));
    fprintf(fid, '   - 剔除阈值: %.3f 像素\n\n', threshold);
    
    % 建议剔除的图像
    highErrorIdx = frameErrors.meanError > threshold;
    fprintf(fid, '2. 建议剔除的高误差图像 (%d个):\n', sum(highErrorIdx));
    if any(highErrorIdx)
        highErrorFrames = frameErrors.imageName(highErrorIdx);
        highErrorValues = frameErrors.meanError(highErrorIdx);
        [sortedValues, sortIdx] = sort(highErrorValues, 'descend');
        for i = 1:length(sortIdx)
            fprintf(fid, '   - %s (误差: %.3f 像素)\n', ...
                highErrorFrames{sortIdx(i)}, sortedValues(i));
        end
    else
        fprintf(fid, '   无\n');
    end
    
    % 考虑剔除的图像
    considerIdx = (frameErrors.meanError > mean(frameErrors.meanError) + std(frameErrors.meanError)) & ~highErrorIdx;
    fprintf(fid, '\n3. 可考虑剔除的偏高误差图像 (%d个):\n', sum(considerIdx));
    if any(considerIdx)
        considerFrames = frameErrors.imageName(considerIdx);
        considerValues = frameErrors.meanError(considerIdx);
        [sortedValues, sortIdx] = sort(considerValues, 'descend');
        for i = 1:min(10, length(sortIdx))
            fprintf(fid, '   - %s (误差: %.3f 像素)\n', ...
                considerFrames{sortIdx(i)}, sortedValues(i));
        end
        if length(sortIdx) > 10
            fprintf(fid, '   ... 还有 %d 个\n', length(sortIdx) - 10);
        end
    else
        fprintf(fid, '   无\n');
    end
    
    % 最佳图像
    [sortedAll, bestIdx] = sort(frameErrors.meanError);
    fprintf(fid, '\n4. 质量最好的图像 (前10个):\n');
    for i = 1:min(10, length(bestIdx))
        idx = bestIdx(i);
        fprintf(fid, '   - %s (误差: %.3f 像素)\n', ...
            frameErrors.imageName{idx}, frameErrors.meanError(idx));
    end
    
    % 优化建议
    fprintf(fid, '\n5. 优化建议:\n');
    
    remainingCount = length(frameErrors.meanError) - sum(highErrorIdx);
    fprintf(fid, '   - 剔除高误差图像后剩余: %d 张\n', remainingCount);
    
    if remainingCount < 20
        fprintf(fid, '   - 警告: 剩余图像较少，建议重新拍摄部分图像\n');
    elseif remainingCount < 50
        fprintf(fid, '   - 注意: 剩余图像数量适中，可以进行标定\n');
    else
        fprintf(fid, '   - 良好: 剩余图像充足，可以获得高质量标定结果\n');
    end
    
    % 计算剔除后的预期误差
    remainingErrors = frameErrors.meanError(~highErrorIdx);
    if ~isempty(remainingErrors)
        fprintf(fid, '   - 剔除后预期平均误差: %.3f 像素\n', mean(remainingErrors));
        fprintf(fid, '   - 改善程度: %.1f%%\n', ...
            100 * (mean(frameErrors.meanError) - mean(remainingErrors)) / mean(frameErrors.meanError));
    end
    
    % 创建剔除脚本
    fprintf(fid, '\n6. 执行剔除的Shell命令:\n');
    fprintf(fid, '   mkdir -p removed_images/left removed_images/right\n');
    if any(highErrorIdx)
        highErrorFrames = frameErrors.imageName(highErrorIdx);
        for i = 1:length(highErrorFrames)
            fprintf(fid, '   mv left_images/%s removed_images/left/\n', highErrorFrames{i});
            fprintf(fid, '   mv right_images/%s removed_images/right/\n', highErrorFrames{i});
        end
    end
    
    fclose(fid);
end
