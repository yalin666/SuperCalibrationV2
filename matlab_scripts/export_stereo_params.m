#修改matlab_scripts/export_stereo_params.m文件
cat > matlab_scripts/export_stereo_params.m << 'EOF'
function export_stereo_params(matFile, outputFile)
    % 将双目标定参数导出为TXT文件
    
    if nargin < 1
        matFile = 'results_optimized/stereoParams_optimized.mat';
    end
    if nargin < 2
        outputFile = 'stereo_calibration_results.txt';
    end
    
    % 加载数据
    data = load(matFile);
    
    % 获取stereoParameters对象
    if isfield(data, 'stereoParamsOptimized')
        params = data.stereoParamsOptimized;
    elseif isfield(data, 'stereoParams')
        params = data.stereoParams;
    else
        error('未找到双目标定参数');
    end
    
    % 打开文件写入
    fid = fopen(outputFile, 'w');
    
    fprintf(fid, '================================================================================\n');
    fprintf(fid, '                          双目相机标定结果\n');
    fprintf(fid, '================================================================================\n');
    fprintf(fid, '生成时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, '标定文件: %s\n', matFile);
    fprintf(fid, '================================================================================\n\n');
    
    % 1. 外参数（相机间的相对位置）
    fprintf(fid, '【1. 外参数 - 相机2相对于相机1的位置】\n');
    fprintf(fid, '----------------------------------------\n');
    baseline = norm(params.TranslationOfCamera2);
    fprintf(fid, '基线长度: %.3f mm\n', baseline);
    fprintf(fid, '平移向量 (mm):\n');
    fprintf(fid, '  Tx = %.3f\n', params.TranslationOfCamera2(1));
    fprintf(fid, '  Ty = %.3f\n', params.TranslationOfCamera2(2));
    fprintf(fid, '  Tz = %.3f\n', params.TranslationOfCamera2(3));
    fprintf(fid, '\n旋转矩阵:\n');
    R = params.RotationOfCamera2;
    fprintf(fid, '  | %.6f  %.6f  %.6f |\n', R(1,1), R(1,2), R(1,3));
    fprintf(fid, '  | %.6f  %.6f  %.6f |\n', R(2,1), R(2,2), R(2,3));
    fprintf(fid, '  | %.6f  %.6f  %.6f |\n', R(3,1), R(3,2), R(3,3));
    
    % 手动计算欧拉角（避免使用rotm2eul）
    % 使用ZYX顺序（Yaw-Pitch-Roll）
    fprintf(fid, '\n欧拉角 (度) - 近似值:\n');
    sy = sqrt(R(1,1)^2 + R(2,1)^2);
    singular = sy < 1e-6;
    
    if ~singular
        x = atan2(R(3,2), R(3,3));
        y = atan2(-R(3,1), sy);
        z = atan2(R(2,1), R(1,1));
    else
        x = atan2(-R(2,3), R(2,2));
        y = atan2(-R(3,1), sy);
        z = 0;
    end
    
    fprintf(fid, '  Roll  = %.3f°\n', x * 180 / pi);
    fprintf(fid, '  Pitch = %.3f°\n', y * 180 / pi);
    fprintf(fid, '  Yaw   = %.3f°\n', z * 180 / pi);
    fprintf(fid, '\n');
    
    % 2. 相机1内参
    fprintf(fid, '【2. 相机1内参数】\n');
    fprintf(fid, '----------------------------------------\n');
    K1 = params.CameraParameters1.IntrinsicMatrix';
    fprintf(fid, '内参矩阵:\n');
    fprintf(fid, '  | %.3f    %.3f    %.3f |\n', K1(1,1), K1(1,2), K1(1,3));
    fprintf(fid, '  | %.3f    %.3f    %.3f |\n', K1(2,1), K1(2,2), K1(2,3));
    fprintf(fid, '  | %.3f    %.3f    %.3f |\n', K1(3,1), K1(3,2), K1(3,3));
    fprintf(fid, '\n焦距 (像素):\n');
    fprintf(fid, '  fx = %.3f\n', K1(1,1));
    fprintf(fid, '  fy = %.3f\n', K1(2,2));
    fprintf(fid, '\n主点 (像素):\n');
    fprintf(fid, '  cx = %.3f\n', K1(1,3));
    fprintf(fid, '  cy = %.3f\n', K1(2,3));
    fprintf(fid, '\n畸变系数:\n');
    fprintf(fid, '  径向畸变: k1=%.6f, k2=%.6f, k3=%.6f\n', ...
        params.CameraParameters1.RadialDistortion(1), ...
        params.CameraParameters1.RadialDistortion(2), ...
        params.CameraParameters1.RadialDistortion(3));
    fprintf(fid, '  切向畸变: p1=%.6f, p2=%.6f\n', ...
        params.CameraParameters1.TangentialDistortion(1), ...
        params.CameraParameters1.TangentialDistortion(2));
    fprintf(fid, '\n');
    
    % 3. 相机2内参
    fprintf(fid, '【3. 相机2内参数】\n');
    fprintf(fid, '----------------------------------------\n');
    K2 = params.CameraParameters2.IntrinsicMatrix';
    fprintf(fid, '内参矩阵:\n');
    fprintf(fid, '  | %.3f    %.3f    %.3f |\n', K2(1,1), K2(1,2), K2(1,3));
    fprintf(fid, '  | %.3f    %.3f    %.3f |\n', K2(2,1), K2(2,2), K2(2,3));
    fprintf(fid, '  | %.3f    %.3f    %.3f |\n', K2(3,1), K2(3,2), K2(3,3));
    fprintf(fid, '\n焦距 (像素):\n');
    fprintf(fid, '  fx = %.3f\n', K2(1,1));
    fprintf(fid, '  fy = %.3f\n', K2(2,2));
    fprintf(fid, '\n主点 (像素):\n');
    fprintf(fid, '  cx = %.3f\n', K2(1,3));
    fprintf(fid, '  cy = %.3f\n', K2(2,3));
    fprintf(fid, '\n畸变系数:\n');
    fprintf(fid, '  径向畸变: k1=%.6f, k2=%.6f, k3=%.6f\n', ...
        params.CameraParameters2.RadialDistortion(1), ...
        params.CameraParameters2.RadialDistortion(2), ...
        params.CameraParameters2.RadialDistortion(3));
    fprintf(fid, '  切向畸变: p1=%.6f, p2=%.6f\n', ...
        params.CameraParameters2.TangentialDistortion(1), ...
        params.CameraParameters2.TangentialDistortion(2));
    fprintf(fid, '\n');
    
    % 4. 标定质量
    fprintf(fid, '【4. 标定质量】\n');
    fprintf(fid, '----------------------------------------\n');
    fprintf(fid, '平均重投影误差: %.4f 像素\n', params.MeanReprojectionError);
    fprintf(fid, '图像分辨率: %d × %d 像素\n', ...
        params.CameraParameters1.ImageSize(2), ...
        params.CameraParameters1.ImageSize(1));
    
    % 5. 立体视觉参数
    fprintf(fid, '\n【5. 立体视觉相关参数】\n');
    fprintf(fid, '----------------------------------------\n');
    avg_focal = (K1(1,1) + K2(1,1)) / 2;
    fprintf(fid, '平均焦距: %.3f 像素\n', avg_focal);
    fprintf(fid, '基线-焦距乘积 (B×f): %.3f mm·像素\n', baseline * avg_focal);
    
    % 深度计算公式: Z = B×f / d，其中d是视差(像素)
    fprintf(fid, '\n深度计算公式: Z = %.3f / d (mm)\n', baseline * avg_focal);
    fprintf(fid, '其中 d 为视差值（像素）\n');
    
    % 计算不同视差对应的深度
    fprintf(fid, '\n视差-深度对应表:\n');
    fprintf(fid, '视差(像素)  深度(mm)   深度(m)\n');
    fprintf(fid, '---------  ---------  --------\n');
    disparities = [1, 5, 10, 20, 30, 40, 50, 60, 80, 100, 120];
    for i = 1:length(disparities)
        d = disparities(i);
        depth_mm = baseline * avg_focal / d;
        depth_m = depth_mm / 1000;
        fprintf(fid, '%9d  %9.1f  %8.2f\n', d, depth_mm, depth_m);
    end
    
    % 6. OpenCV格式参数（方便其他程序使用）
    fprintf(fid, '\n【6. OpenCV/Python格式参数】\n');
    fprintf(fid, '----------------------------------------\n');
    fprintf(fid, '# 直接复制以下内容到Python程序中使用\n\n');
    
    fprintf(fid, '# Camera 1 Matrix\n');
    fprintf(fid, 'K1 = np.array([[%.6f, %.6f, %.6f],\n', K1(1,1), K1(1,2), K1(1,3));
    fprintf(fid, '               [%.6f, %.6f, %.6f],\n', K1(2,1), K1(2,2), K1(2,3));
    fprintf(fid, '               [%.6f, %.6f, %.6f]])\n\n', K1(3,1), K1(3,2), K1(3,3));
    
    fprintf(fid, '# Camera 1 Distortion\n');
    fprintf(fid, 'D1 = np.array([%.6f, %.6f, %.6f, %.6f, %.6f])\n\n', ...
        params.CameraParameters1.RadialDistortion(1), ...
        params.CameraParameters1.RadialDistortion(2), ...
        params.CameraParameters1.TangentialDistortion(1), ...
        params.CameraParameters1.TangentialDistortion(2), ...
        params.CameraParameters1.RadialDistortion(3));
    
    fprintf(fid, '# Camera 2 Matrix\n');
    fprintf(fid, 'K2 = np.array([[%.6f, %.6f, %.6f],\n', K2(1,1), K2(1,2), K2(1,3));
    fprintf(fid, '               [%.6f, %.6f, %.6f],\n', K2(2,1), K2(2,2), K2(2,3));
    fprintf(fid, '               [%.6f, %.6f, %.6f]])\n\n', K2(3,1), K2(3,2), K2(3,3));
    
    fprintf(fid, '# Camera 2 Distortion\n');
    fprintf(fid, 'D2 = np.array([%.6f, %.6f, %.6f, %.6f, %.6f])\n\n', ...
        params.CameraParameters2.RadialDistortion(1), ...
        params.CameraParameters2.RadialDistortion(2), ...
        params.CameraParameters2.TangentialDistortion(1), ...
        params.CameraParameters2.TangentialDistortion(2), ...
        params.CameraParameters2.RadialDistortion(3));
    
    fprintf(fid, '# Rotation Matrix\n');
    fprintf(fid, 'R = np.array([[%.9f, %.9f, %.9f],\n', R(1,1), R(1,2), R(1,3));
    fprintf(fid, '              [%.9f, %.9f, %.9f],\n', R(2,1), R(2,2), R(2,3));
    fprintf(fid, '              [%.9f, %.9f, %.9f]])\n\n', R(3,1), R(3,2), R(3,3));
    
    fprintf(fid, '# Translation Vector\n');
    fprintf(fid, 'T = np.array([[%.6f], [%.6f], [%.6f]])\n\n', ...
        params.TranslationOfCamera2(1), ...
        params.TranslationOfCamera2(2), ...
        params.TranslationOfCamera2(3));
    
    fprintf(fid, '# Baseline (mm)\n');
    fprintf(fid, 'baseline = %.3f\n', baseline);
    
    fprintf(fid, '\n================================================================================\n');
    
    fclose(fid);
    
    fprintf('标定参数已保存到: %s\n', outputFile);
    
    % 显示关键信息
    fprintf('\n关键参数摘要:\n');
    fprintf('  基线长度: %.3f mm\n', baseline);
    fprintf('  平均重投影误差: %.4f 像素\n', params.MeanReprojectionError);
    fprintf('  平均焦距: %.3f 像素\n', avg_focal);
    fprintf('\n详细参数请查看: %s\n', outputFile);
end
EOF

echo "已更新 matlab_scripts/export_stereo_params.m 文件"
