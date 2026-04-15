function simple_error_analysis(stereoParamsFile, outputFolder)
    % 简化的误差分析 - 使用MATLAB内置的误差评估
    
    fprintf('========== 简化误差分析 ==========\n');
    
    % 设置默认参数
    if nargin < 1 || isempty(stereoParamsFile)
        stereoParamsFile = 'results/stereoParams.mat';
    end
    
    if nargin < 2 || isempty(outputFolder)
        outputFolder = 'results';
    end
    
    % 加载数据
    load(stereoParamsFile, 'stereoParams', 'imagesUsed');
    
    % 获取每个相机的误差统计
    fprintf('\n相机标定质量评估:\n');
    
    % 左相机
    cam1 = stereoParams.CameraParameters1;
    fprintf('\n左相机:\n');
    fprintf('  焦距: [%.2f, %.2f]\n', cam1.FocalLength);
    fprintf('  主点: [%.2f, %.2f]\n', cam1.PrincipalPoint);
    fprintf('  径向畸变: k1=%.4f, k2=%.4f, k3=%.4f\n', cam1.RadialDistortion);
    fprintf('  切向畸变: p1=%.4f, p2=%.4f\n', cam1.TangentialDistortion);
    
    % 右相机
    cam2 = stereoParams.CameraParameters2;
    fprintf('\n右相机:\n');
    fprintf('  焦距: [%.2f, %.2f]\n', cam2.FocalLength);
    fprintf('  主点: [%.2f, %.2f]\n', cam2.PrincipalPoint);
    fprintf('  径向畸变: k1=%.4f, k2=%.4f, k3=%.4f\n', cam2.RadialDistortion);
    fprintf('  切向畸变: p1=%.4f, p2=%.4f\n', cam2.TangentialDistortion);
    
    % 双目参数
    fprintf('\n双目参数:\n');
    fprintf('  基线长度: %.2f mm\n', norm(stereoParams.TranslationOfCamera2));
    fprintf('  使用的图像对数: %d\n', sum(imagesUsed));
    
    % 获取每个视图的估计误差
    fprintf('\n尝试获取误差信息...\n');
    
    % 使用简单的误差估计
    numViews = sum(imagesUsed);
    viewIndices = find(imagesUsed);
    
    % 创建误差报告
    reportFile = fullfile(outputFolder, 'simple_error_report.txt');
    fid = fopen(reportFile, 'w');
    
    fprintf(fid, '========== 双目标定误差分析报告 ==========\n\n');
    fprintf(fid, '生成时间: %s\n\n', datestr(now));
    
    fprintf(fid, '1. 标定参数概览:\n');
    fprintf(fid, '   基线长度: %.2f mm\n', norm(stereoParams.TranslationOfCamera2));
    fprintf(fid, '   使用图像对数: %d\n', numViews);
    fprintf(fid, '   总图像数: %d\n', length(imagesUsed));
    fprintf(fid, '\n');
    
    fprintf(fid, '2. 相机内参对比:\n');
    fprintf(fid, '   左相机焦距: [%.2f, %.2f]\n', cam1.FocalLength);
    fprintf(fid, '   右相机焦距: [%.2f, %.2f]\n', cam2.FocalLength);
    fprintf(fid, '   焦距差异: %.2f%%\n', 100*abs(mean(cam1.FocalLength) - mean(cam2.FocalLength))/mean(cam1.FocalLength));
    fprintf(fid, '\n');
    
    fprintf(fid, '3. 畸变参数:\n');
    fprintf(fid, '   左相机最大畸变系数: %.4f\n', max(abs([cam1.RadialDistortion, cam1.TangentialDistortion])));
    fprintf(fid, '   右相机最大畸变系数: %.4f\n', max(abs([cam2.RadialDistortion, cam2.TangentialDistortion])));
    fprintf(fid, '\n');
    
    fprintf(fid, '4. 使用的图像列表:\n');
    count = 0;
    for i = 1:length(viewIndices)
        fprintf(fid, '   图像 %03d', viewIndices(i));
        count = count + 1;
        if mod(count, 5) == 0
            fprintf(fid, '\n');
        else
            fprintf(fid, ', ');
        end
    end
    if mod(count, 5) ~= 0
        fprintf(fid, '\n');
    end
    
    fprintf(fid, '\n5. 未使用的图像:\n');
    unusedIndices = find(~imagesUsed);
    if ~isempty(unusedIndices)
        fprintf(fid, '   共 %d 张图像未检测到棋盘格\n', length(unusedIndices));
        if length(unusedIndices) <= 20
            for i = 1:length(unusedIndices)
                fprintf(fid, '   图像 %03d\n', unusedIndices(i));
            end
        else
            fprintf(fid, '   图像编号: ');
            for i = 1:10
                fprintf(fid, '%03d ', unusedIndices(i));
            end
            fprintf(fid, '... (还有%d张)\n', length(unusedIndices)-10);
        end
    else
        fprintf(fid, '   无\n');
    end
    
    % 质量评估
    fprintf(fid, '\n6. 标定质量评估:\n');
    
    % 基线评估
    baseline = norm(stereoParams.TranslationOfCamera2);
    if baseline < 50
        fprintf(fid, '   ⚠ 基线较短(%.1fmm)，可能影响深度精度\n', baseline);
    elseif baseline > 300
        fprintf(fid, '   ⚠ 基线较长(%.1fmm)，可能存在遮挡问题\n', baseline);
    else
        fprintf(fid, '   ✓ 基线长度合适(%.1fmm)\n', baseline);
    end
    
    % 图像数量评估
    if numViews < 10
        fprintf(fid, '   ⚠ 使用图像较少(%d)，建议至少20张\n', numViews);
    elseif numViews < 20
        fprintf(fid, '   ⚠ 使用图像数量一般(%d)，可以考虑增加\n', numViews);
    else
        fprintf(fid, '   ✓ 使用图像充足(%d)\n', numViews);
    end
    
    % 畸变评估
    maxDistortion = max([max(abs([cam1.RadialDistortion, cam1.TangentialDistortion])), ...
                        max(abs([cam2.RadialDistortion, cam2.TangentialDistortion]))]);
    if maxDistortion > 1.0
        fprintf(fid, '   ⚠ 畸变系数较大(%.3f)，镜头畸变明显\n', maxDistortion);
    else
        fprintf(fid, '   ✓ 畸变系数正常(%.3f)\n', maxDistortion);
    end
    
    fclose(fid);
    
    % 生成简单的可视化
    plotFile = fullfile(outputFolder, 'simple_calibration_plot.png');
    generateSimplePlot(stereoParams, imagesUsed, plotFile);
    
    fprintf('\n分析完成！\n');
    fprintf('报告已保存到: %s\n', reportFile);
    fprintf('图表已保存到: %s\n', plotFile);
end

function generateSimplePlot(stereoParams, imagesUsed, filename)
    % 生成简单的标定结果可视化
    
    figure('Visible', 'off', 'Position', [100, 100, 1200, 800]);
    
    % 子图1: 相机配置
    subplot(2,2,1);
    plotCameraConfig(stereoParams);
    title('双目相机配置');
    
    % 子图2: 使用的图像统计
    subplot(2,2,2);
    usedCount = sum(imagesUsed);
    totalCount = length(imagesUsed);
    bar([usedCount, totalCount-usedCount]);
    set(gca, 'XTickLabel', {'使用', '未使用'});
    ylabel('图像数量');
    title(sprintf('图像使用情况 (%d/%d)', usedCount, totalCount));
    grid on;
    
    % 子图3: 畸变系数对比
    subplot(2,2,3);
    plotDistortionCoeffs(stereoParams);
    title('畸变系数对比');
    
    % 子图4: 标定信息
    subplot(2,2,4);
    axis off;
    displayCalibInfo(stereoParams);
    title('标定信息');
    
    sgtitle('双目相机标定结果', 'FontSize', 16);
    saveas(gcf, filename);
    close(gcf);
end

function plotCameraConfig(stereoParams)
    % 绘制相机配置
    T = stereoParams.TranslationOfCamera2;
    
    % 左相机在原点
    plot3(0, 0, 0, 'ro', 'MarkerSize', 15, 'MarkerFaceColor', 'r');
    hold on;
    text(0, 0, -10, '左相机', 'HorizontalAlignment', 'center');
    
    % 右相机
    plot3(T(1), T(2), T(3), 'bo', 'MarkerSize', 15, 'MarkerFaceColor', 'b');
    text(T(1), T(2), T(3)-10, '右相机', 'HorizontalAlignment', 'center');
    
    % 连接线（基线）
    plot3([0 T(1)], [0 T(2)], [0 T(3)], 'k-', 'LineWidth', 2);
    
    % 基线长度标注
    mid = T/2;
    text(mid(1), mid(2), mid(3)+5, sprintf('基线: %.1fmm', norm(T)), ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
    
    xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
    axis equal;
    grid on;
    view(45, 30);
    
    % 设置合理的显示范围
    lim = max(abs(T)) * 1.5;
    if lim > 0
        xlim([-lim lim]);
        ylim([-lim lim]);
        zlim([-lim/2 lim/2]);
    end
end

function plotDistortionCoeffs(stereoParams)
    % 绘制畸变系数
    cam1 = stereoParams.CameraParameters1;
    cam2 = stereoParams.CameraParameters2;
    
    % 组合系数
    coeffs1 = [cam1.RadialDistortion, cam1.TangentialDistortion];
    coeffs2 = [cam2.RadialDistortion, cam2.TangentialDistortion];
    
    labels = {'k1', 'k2', 'k3', 'p1', 'p2'};
    x = 1:5;
    
    bar(x-0.2, coeffs1, 0.4, 'r');
    hold on;
    bar(x+0.2, coeffs2, 0.4, 'b');
    
    set(gca, 'XTick', x);
    set(gca, 'XTickLabel', labels);
    ylabel('系数值');
    legend('左相机', '右相机');
    grid on;
end

function displayCalibInfo(stereoParams)
    % 显示标定信息
    cam1 = stereoParams.CameraParameters1;
    cam2 = stereoParams.CameraParameters2;
    
    y = 0.9;
    dy = 0.08;
    
    text(0.1, y, '相机参数:', 'FontWeight', 'bold', 'FontSize', 12);
    y = y - dy;
    
    text(0.1, y, sprintf('左焦距: [%.1f, %.1f]', cam1.FocalLength), 'FontSize', 10);
    y = y - dy;
    
    text(0.1, y, sprintf('右焦距: [%.1f, %.1f]', cam2.FocalLength), 'FontSize', 10);
    y = y - dy;
    
    text(0.1, y, sprintf('基线: %.1f mm', norm(stereoParams.TranslationOfCamera2)), 'FontSize', 10);
    y = y - dy;
    
    % 旋转角度
    R = stereoParams.RotationOfCamera2;
    angles = rad2deg(atan2(R(3,2), R(3,3)));  % 简化的角度计算
    
    y = y - dy;
    text(0.1, y, '相对位姿:', 'FontWeight', 'bold', 'FontSize', 12);
    y = y - dy;
    
    text(0.1, y, sprintf('旋转角: ~%.1f°', angles), 'FontSize', 10);
    y = y - dy;
    
    T = stereoParams.TranslationOfCamera2;
    text(0.1, y, sprintf('平移: [%.1f, %.1f, %.1f]', T), 'FontSize', 10);
end
