function runPhase(obj, currentFace, currentRepeatTimes, globalIterNum, currentIter)
    numGpus  = numel(obj.gpus);
    outputBlobID = obj.data.outId.(currentFace);
    accumulateOutBlobs = cell(size(outputBlobID));
    accumulateOutBlobsNum = numel(accumulateOutBlobs);

    optface = obj.pha_opt.(currentFace);

    % Create options for fb()
    optface.disableDropout  = optface.learningRate == 0;
    optface.outputBlobCount = cellfun(@numel, obj.data.connectId.(currentFace));
    optface.name = currentFace;
    optface.gpuMode = numGpus >= 1;
    optface.gpus = obj.gpus;

    % Find initial weight learning rate ~= 0 to update them
    needToUpdatedWeightsInd = find(~obj.net.weightsIsMisc & ~cellfun(@isempty,obj.net.weights));
    if ~isempty(optface.backpropToLayer)
        nw = [];
        for ww = numel(obj.net.phase.(currentFace)):-1:1
            l = obj.net.phase.(currentFace){ww};
            if isfield(l, 'weights')
                nw = [nw, l.weights]; %#ok
            end
            if strcmp(optface.backpropToLayer, l.name)
                break;
            end
        end
        [~,wind] = setdiff(needToUpdatedWeightsInd,nw);
        needToUpdatedWeightsInd(wind) = [];
    end

    if numGpus > 0
        dzdy = gpuArray.ones(1, 'single');
    else
        dzdy = single(1);
    end

    % Calculate total iteration number, current phase total iteration number
    currentPhaseTotalIter = (currentRepeatTimes-1)*optface.numToNext+currentIter;
    phaseTime = tic;
    pstart = tic;
    obj.net.weightsDiffCount = obj.net.weightsDiffCount*int32(0);
    layerIDs = obj.net.noSubPhase.(currentFace);
    if obj.clearDataOnPhaseStart
        obj.clearData();
    end


    % Running time constant variables
    % -------------------------------
    count = 1;
    count_per_display = 1;
    ss = 1:optface.iter_size;
    sb = 1:accumulateOutBlobsNum;
    weightsNUMEL = [];
    gFun = obj.solverGPUFun;
    for i=layerIDs
        obj.net.layers{i}.no = i;
    end
    % -------------------------------

    for t = currentIter:optface.numToNext
        % set learning rate
        learningRate = optface.learningRatePolicy(globalIterNum, currentPhaseTotalIter, optface.learningRate, optface.learningRateGamma, optface.learningRatePower, optface.learningRateSteps);

        % set currentIter
        optface.currentIter = t;

        for s=ss
            % evaluate CNN
            optface.accumulate = s > 1;
            optface.freezeDropout = s > 1;
            [obj.data,obj.net] = obj.forwardbackward(obj.data, obj.net, currentFace, layerIDs, optface, dzdy);

            % accumulate backprop errors
            % assume all output blobs are loss-like blobs
            for ac = sb
                if isempty(accumulateOutBlobs{ac})
                    accumulateOutBlobs{ac} = obj.data.val{outputBlobID(ac)};
                else
                    accumulateOutBlobs{ac} = accumulateOutBlobs{ac} + obj.data.val{outputBlobID(ac)};
                end
            end
        end
        obj.net.weightsDiffCount = obj.net.weightsDiffCount*int32(0);

        if optface.learningRate ~= 0
            if numGpus == 0
                obj.net = obj.updateWeightCPU(obj.net, learningRate, optface.weightDecay, optface.momentum, optface.iter_size, needToUpdatedWeightsInd);
                %net = solver.solve(optface, learningRate, net, res, needToUpdatedWeightsInd);
            else
                if isempty(weightsNUMEL)
                    weightsNUMEL = zeros(size(obj.net.weights),'single');
                    for i=1:numel(needToUpdatedWeightsInd)
                        weightsNUMEL(needToUpdatedWeightsInd(i)) = numel(obj.net.weights{needToUpdatedWeightsInd(i)});
                    end
                    gFun.GridSize = ceil( max(weightsNUMEL)/obj.MaxThreadsPerBlock );
                end
                if numGpus == 1
                    obj.net = obj.updateWeightGPU(obj.net, learningRate, optface.weightDecay, optface.momentum, optface.iter_size, needToUpdatedWeightsInd, gFun, weightsNUMEL);
                else
                    labBarrier();
                    %accumulate weight gradients from other labs
                    %res.dzdw = gop(@(a,b) cellfun(@plus, a,b, 'UniformOutput', false), res.dzdw);
                    for nz=1:numel(obj.net.weightsDiff)
                        obj.net.weightsDiff{nz} = gop(@plus, obj.net.weightsDiff{nz});
                    end
                    %net = solver.solve(optface, learningRate, net, res, needToUpdatedWeightsInd);
                    obj.net = obj.updateWeightGPU(obj.net, learningRate, optface.weightDecay, optface.momentum, optface.iter_size, needToUpdatedWeightsInd, gFun, weightsNUMEL);
                end
            end
        end

        % Print learning statistics
        if mod(count, optface.displayIter) == 0 || (count == 1 && optface.showFirstIter) || t==optface.numToNext
            if obj.showDate
                dStr = datestr(now, '[mmdd HH:MM:SS.FFF ');
            else
                dStr = '';
            end
            if optface.learningRate ~= 0
                preStr = [dStr, sprintf('Lab%d—%s] F%d/G%d lr(%g) ', labindex, currentFace,currentPhaseTotalIter, globalIterNum, learningRate)];
            else
                preStr = [dStr, sprintf('Lab%d—%s] F%d/G%d ', labindex, currentFace,currentPhaseTotalIter, globalIterNum)];
            end
            
            for ac = 1:accumulateOutBlobsNum
                if ~isempty(accumulateOutBlobs{ac})
                    fprintf(preStr);
                    fprintf('%s(%.6g) ', obj.data.names{outputBlobID(ac)}, accumulateOutBlobs{ac}./(optface.iter_size*count_per_display)); % this is a per-batch avg., not output avg.
                end
                if ac~=numel(accumulateOutBlobs)
                    fprintf('\n');
                end
            end

            fprintf('%.2fs(%.2f iter/s)\n', toc(phaseTime), count_per_display/toc(phaseTime));
            phaseTime = tic;
            accumulateOutBlobs = cell(size(outputBlobID));
            count_per_display = 0;
        end

        % Save model
        if ~isempty(optface.numToSave) && mod(count, optface.numToSave) == 0
            if numGpus > 1
                labBarrier();
            end
            if labindex == 1 % only one worker can save the model
                obj.save(obj.saveFilePath(globalIterNum));
            end
            if numGpus > 1
                labBarrier();
            end
        end

        count = count+1;
        count_per_display = count_per_display+1;
        globalIterNum = globalIterNum+1;
        currentPhaseTotalIter = currentPhaseTotalIter+1;

    end
    %obj.data.val = cell(size(data.val));
    %obj.data.diff = cell(size(data.diff));
    obj.globalIter = globalIterNum;
    toc(pstart);
end