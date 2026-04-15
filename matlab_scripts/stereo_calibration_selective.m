function stereo_calibration_selective(leftImagesFolder, rightImagesFolder, squareSize, outputFolder, varargin)
    % STEREO_CALIBRATION_SELECTIVE - 带图像选择的迭代式双目相机标定
    %
    % 输入参数:
    %   leftImagesFolder  - 左相机图像文件夹路径
    %   rightImagesFolder - 右相机图像文件夹路径
    %   squareSize       - 标定板方格大小（毫米）
    %   outputFolder     - 输出文件夹路径
    %
    % 可选参数（名称-值对）:
    %   'MaxIterations'    - 最大迭代次数（默认: 10）
    %   'ErrorThreshold'   - 误差阈值系数（默认: 1.5）
    %   'MinImages'        - 最少保留图像数（默认: 40）
    %   'TargetImages'     - 目标图像数
    %   'TargetError'      - 目标平均误差
    %   'SelectionStrategy'- 图像选择策略: 'best', 'distributed', 'hybrid'
    
    % 解析输入参数
    p = inputParser;
    addRequired(p, 'leftImagesFolder', @ischar);
    addRequired(p, 'rightImagesFolder', @ischar);
    addRequired(p, 'squareSize', @isnumeric);
    addRequired(p, 'outputFolder', @ischar);
    addParameter(p, 'MaxIterations', 10, @isnumeric);
    addParameter(p, 'ErrorThreshold', 1.5, @isnumeric);
    addParameter(p, 'MinImages', 40, @isnumeric);
    addParameter(p, 'TargetImages', [], @isnumeric);
    addParameter(p, 'TargetError', [], @isnumeric);
    addParameter(p, 'SelectionStrategy', 'best', @ischar);
    
    parse(p, leftImagesFolder, rightImagesFolder, squareSize, outputFolder, varargin{:});
    params = p.Results;
    
    % 创建输出目录
    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end
    
    % 打开日志文件
    logFile = fullfile(outputFolder, 'iterative_log.txt');
    fid = fopen(logFile, 'w');
    logMessage(fid, '===== 带图像选择的迭代式双目标定 =====');
    logMessage(fid, sprintf('开始时间: %s', datestr(now)));
    logMessage(fid, sprintf('选择策略: %s', params.SelectionStrategy));
    if ~isempty(params.TargetImages)
        logMessage(fid, sprintf('目标图像数: %d', params.TargetImages));
    end
    if ~isempty(params.TargetError)
        logMessage(fid, sprintf('目标误差: %.3f 像素', params.TargetError));
    end
    logMessage(fid, '');
    
    % 获取图像列表
    leftImages = imageDatastore(leftImagesFolder);
    rightImages = imageDatastore(rightImagesFolder);
    imageFiles = leftImages.Files;
    numImages = length(imageFiles);
    
    logMessage(fid, sprintf('总图像数: %d', numImages));
    
    % 检测所有图像的标定板角点
    fprintf('检测标定板角点...\n');
    [imagePoints, boardSize, imagesUsed] = detectCalibrationPoints(leftImages, rightImages, squareSize);
    
    if sum(imagesUsed) < params.MinImages
        error('检测到的有效图像数量不足！');
    end
    
    % 生成世界坐标
    worldPoints = generateCheckerboardPoints(boardSize, squareSize);
    
    % 获取图像尺寸
    I = readimage(leftImages, 1);
    imageSize = size(I, 1:2);
    
    % 初始化变量
    currentImages = find(imagesUsed);
    bestParams = [];
    bestError = inf;
    iterationResults = [];
    
    % 迭代优化
    for iter = 1:params.MaxIterations
        logMessage(fid, sprintf('\n迭代 %d:', iter));
        logMessage(fid, sprintf('当前图像数: %d', length(currentImages)));
        
        % 使用当前图像集进行标定
        currentImagePoints(:,:,:,1) = imagePoints(:,:,currentImages,1);
        currentImagePoints(:,:,:,2) = imagePoints(:,:,currentImages,2);
        
        [stereoParams, pairsUsed, errors] = estimateCameraParameters(...
            currentImagePoints, worldPoints, ...
            'EstimateSkew', false, ...
            'EstimateTangentialDistortion', false, ...
            'NumRadialDistortionCoefficients', 2, ...
            'ImageSize', imageSize);
        
        % 计算误差统计
        meanError = mean(errors);
        stdError = std(errors);
        
        logMessage(fid, sprintf('平均误差: %.3f 像素', meanError));
        logMessage(fid,
