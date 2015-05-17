function o = deconvolution(varargin)
%DECONVOLUTION Compute mean class accuracy for you

o.name         = 'Deconvolution';
o.generateLoss = false;
o.setup        = @setup;
o.forward      = @forward;
o.backward     = @backward;


default_weight_param = {
            'name' {'', ''}         ... %empty names means use autogenerated name
    'enable_terms' [true, true]     ... 
       'generator' {@nn.generator.uniform, @nn.generator.constant} ...
       'generator_param' {[], []}   ... %default param
    'learningRate' single([1 1])    ...
     'weightDecay' single([1 1])  
};
default_deconvolution_param = {
      'num_output' 1     ...
     'kernel_size' [3 3] ...
            'crop' [0 0] ...
      'upsampling' [1 1] ...
};

%
topSizes = [];

    function [resource, topSizes, param] = setup(l, bottomSizes)
        % resource only have .weights
        % if you have other outputs you want to save or share
        % you can set its learning rate to zero to prevent update


        if isfield(l, 'weight_param')
            wp1 = nn.utils.vararginHelper(default_weight_param, l.weight_param);
        else
            wp1 = nn.utils.vararginHelper(default_weight_param, default_weight_param);
        end
        if isfield(l, 'deconvolution_param')
            wp2 = nn.utils.vararginHelper(default_deconvolution_param, l.deconvolution_param);
        else
            wp2 = nn.utils.vararginHelper(default_deconvolution_param, default_deconvolution_param);
        end
        if ~any(wp1.enable_terms)
            error('At least enable one weight.');
        end


        assert(numel(l.bottom)==1);
        assert(numel(l.top)==1);


        kernel_size = wp2.kernel_size;
        if numel(kernel_size) == 1
            kernel_size = [kernel_size, kernel_size];
        end
        stride_size = wp2.upsampling;
        if numel(stride_size) == 1
            stride_size = [stride_size, stride_size];
        end
        pad_size = wp2.crop;
        if numel(pad_size) == 1
            pad_size = [pad_size, pad_size, pad_size, pad_size];
        elseif numel(pad_size) == 2
            pad_size = [pad_size(1), pad_size(1), pad_size(2), pad_size(2)];
        end


        resource.weight = {[],[]};
        btmSize = bottomSizes{1};
        topSizes = {[ceil([(btmSize(1)-1)*stride_size(1)+pad_size(1)+pad_size(2)+kernel_size(1), ...
                           (btmSize(2)-1)*stride_size(2)+pad_size(3)+pad_size(4)+kernel_size(2)]), ...
                            wp2.num_output, btmSize(4)]};


        if wp1.enable_terms(1)
            resource.weight{1} = wp1.generator{1}([kernel_size(1), kernel_size(2), bottomSizes{1}(3), wp2.num_output], wp1.generator_param{1});
        end

        if wp1.enable_terms(2)
            resource.weight{2} = wp1.generator{2}([1, wp2.num_output], wp1.generator_param{2});
        end

        %return updated param
        param.weight_param = wp1;
        param.deconvolution_param = wp2;
    end


    function [outputBlob, weights] = forward(opts, l, weights, blob)
        outputBlob{1} = vl_nnconvt(blob{1}, weights{1}, weights{2}, 'Crop', l.deconvolution_param.crop, 'Upsampling', l.deconvolution_param.upsampling);
    end


    function [mydzdx, mydzdw] = backward(opts, l, weights, blob, dzdy, mydzdw, mydzdwCumu)
        %numel(mydzdx) = numel(blob), numel(mydzdw) = numel(weights)

        if mydzdwCumu(1) && mydzdwCumu(2)
            [ mydzdx{1}, a, b ]= ...
                             vl_nnconvt(blob{1}, weights{1}, weights{2}, dzdy{1}, 'Crop', l.deconvolution_param.crop, 'Upsampling', l.deconvolution_param.upsampling);
            mydzdw{1} = mydzdw{1} + a;
            mydzdw{2} = mydzdw{2} + b;
        elseif mydzdwCumu(1)
            [ mydzdx{1}, outputdzdw, mydzdw{2} ]= ...
                             vl_nnconvt(blob{1}, weights{1}, weights{2}, dzdy{1}, 'Crop', l.deconvolution_param.crop, 'Upsampling', l.deconvolution_param.upsampling);
            mydzdw{1} = mydzdw{1} + outputdzdw;
        elseif mydzdwCumu(2)
            [ mydzdx{1}, mydzdw{1}, outputdzdw ]= ...
                             vl_nnconvt(blob{1}, weights{1}, weights{2}, dzdy{1}, 'Crop', l.deconvolution_param.crop, 'Upsampling', l.deconvolution_param.upsampling);
            mydzdw{2} = mydzdw{2} + outputdzdw;
        else
            [ mydzdx{1}, mydzdw{1}, mydzdw{2} ]= ...
                             vl_nnconvt(blob{1}, weights{1}, weights{2}, dzdy{1}, 'Crop', l.deconvolution_param.crop, 'Upsampling', l.deconvolution_param.upsampling);
        end

    end

end