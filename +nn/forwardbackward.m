function res = forwardbackward(net, x, dzdy, res, opts)
%FORWARDBACKWARD  Evaluates a neural network built with buildnet.m
%
%
%  Forward:
%    'res' is a structure, each field is the tops of layers
%  Backward:
%    'res' is a cell array, each cell is corresponds to a specific layer
%
%  Details:
%    Weights can be shared, if your weight_name set to the same name.
%    (eg. layers.weights)
%    Tops can be shared. (eg. forward of res)
%    Diffs cannot be shared. (eg. backward of res)
%
%  NOTICE
%  if your layer produces .misc, you need to maintain its gpu/cpu array consistency.
%
%  Default values: (for faster computation, disable value checking, you should
%                   provide all of the following options)
%
%  
%  opts.accumulate = false;
%  opts.conserveMemory = false;
%  opts.sync = false;
%  opts.disableDropout = false;
%  opts.freezeDropout = false;
%  opts.visitLayerID = 1:numel(net.layers);
%  opts.gpuMode = false;
%  opts.doder = false;
forget = opts.conserveMemory & ~opts.doder;
waitGPU = opts.gpuMode & opts.sync;

if isempty(res)
    if opts.gpuMode
        res.blob  = num2cell(gpuArray.zeros(1, numel(net.blobNames), 'single'));
        res.dzdx  = num2cell(gpuArray.zeros(1, numel(net.blobNames), 'single')); % each cell contains another cell, and the inner cell's length is respected to the number of bottoms that a layer accepts
        res.dzdw  = num2cell(gpuArray.zeros(1, numel(net.weightsNames), 'single')); % Each dzdw{w} corresponds to a net.weights{w}, no separate dzdw for each layer
    else
        res.blob  = num2cell(zeros(1, numel(net.blobNames), 'single'));
        res.dzdx  = num2cell(zeros(1, numel(net.blobNames), 'single')); % each cell contains another cell, and the inner cell's length is respected to the number of bottoms that a layer accepts
        res.dzdw  = num2cell(zeros(1, numel(net.weightsNames), 'single')); % Each dzdw{w} corresponds to a net.weights{w}, no separate dzdw for each layer
    end
    res.dzdwVisited = false(size(res.dzdw));
end

for i = fieldnames(x)'
    name2Ind = net.blobNamesIndex.(i{1});
    res.blob{name2Ind} = x.(i{1}); %Because x is a structure, eg. x = struct('data',[],'label',[])
end

for i = opts.visitLayerID
    l = net.layers{i};
  
    % if a layer don't generate output, it still should fill topBlob as {[],[],...}
    %if ~isempty(l.weights)
        [res.blob(l.top), net.weights(l.weights)] = net.layerobjs{i}.forward(opts, l, net.weights(l.weights), res.blob(l.bottom));
    %else
    %    [res.blob(l.top), ~] = net.layerobjs{i}.forward(opts, l, {}, res.blob(l.bottom));
    %end

    % optionally forget intermediate results
    if forget && (~isfield(l, 'rememberOutput') || ~l.rememberOutput)
        if opts.gpuMode
            res.blob(l.top) = {gpuArray(single(0))};
        else
            res.blob(l.top) = {single(0)};
        end
    end
    if waitGPU
        % This should make things slower, but on MATLAB 2014a it is necessary
        % for any decent performance.
        wait(gpuDevice);
    end
end


if opts.doder

    % Make output blobs have their derivatives
    % consider the derivatives of all output blobs are
    % scalers, which are 1
    % You can make a weight scaler for loss, just write a
    % custom layer that multiplies the scaler onto it
    outputBlob = cellfun('isempty', net.blobConnectId);
    res.dzdx(outputBlob) = {dzdy};
  
    for i = opts.visitLayerID(end:-1:1)
        l = net.layers{i};
    
        [tmpdzdx, res.dzdw(l.weights)] = net.layerobjs{i}.backward(opts, l, net.weights(l.weights), res.blob(l.bottom), res.dzdx(l.top), res.dzdw(l.weights), res.dzdwVisited(l.weights));
        res.dzdwVisited(l.weights) = true;
        % Don't try to clear res.dzdx or res.dzdw at first, you will get terrble performace!!
        % If you try to clear them at first so you can get rid of if-statement of opts.accumulate
        % , the performance will drain a lot.
        dzdxEmpty = ~cellfun('isempty', tmpdzdx);
        if opts.accumulate
            for b = find(dzdxEmpty)
                if any(net.blobConnectId(l.bottom(b)) == i)
                    res.dzdx{l.bottom(b)} = res.dzdx{l.bottom(b)} + tmpdzdx{b};
                else
                    res.dzdx(l.bottom(b)) = tmpdzdx(b);
                end
            end
        else
            res.dzdx(l.bottom(dzdxEmpty)) = tmpdzdx(dzdxEmpty);
        end
        
        %{
        % be careful of modifying this.
        dzdwEmpty = ~cellfun('isempty', tmpdzdw);
        dzdwEmpty2 = dzdwEmpty & ~res.dzdwVisited(l.weights);
        for w = find(dzdwEmpty & res.dzdwVisited(l.weights))
            res.dzdw{l.weights(w)} = res.dzdw{l.weights(w)} + tmpdzdw{w};
        end
        % blow is slightly slower than loop (above)
        %res.dzdw(l.weights(dzdwEmpty1)) = cellfun(@plus, res.dzdw(l.weights(dzdwEmpty1)), tmpdzdw(dzdwEmpty1), 'UniformOutput', false);
        res.dzdw(l.weights(dzdwEmpty2)) = tmpdzdw(dzdwEmpty2);
        res.dzdwVisited(l.weights(dzdwEmpty)) = true;
        %}
    
        if opts.conserveMemory %delete used dzdx{top}, no need to consider loss or accuracy, because der(loss)=1, and accuracy has no backward computation
            if opts.gpuMode
                res.dzdx(l.top) = {gpuArray(single(0))};
            else
                res.dzdx(l.top) = {single(0)};
            end
        end
        if waitGPU
            wait(gpuDevice);
        end
    end
end
