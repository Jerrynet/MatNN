function o = convolution(varargin)
%CONVOLUTION Compute mean class accuracy for you

o.name         = 'Convolution';
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
default_convolution_param = {
      'num_output' 1     ...
     'kernel_size' [3 3] ...
             'pad' [0 0] ...
          'stride' [1 1] ...
};

    function [resource, topSizes, param] = setup(l, bottomSizes)
        % resource only have .weight
        % if you have other outputs you want to save or share
        % you can set its learning rate to zero to prevent update


        if isfield(l, 'weight_param')
            wp1 = nn.utils.vararginHelper(default_weight_param, l.weight_param);
        else
            wp1 = nn.utils.vararginHelper(default_weight_param, default_weight_param);
        end
        if isfield(l, 'convolution_param')
            wp2 = nn.utils.vararginHelper(default_convolution_param, l.convolution_param);
        else
            wp2 = nn.utils.vararginHelper(default_convolution_param, default_convolution_param);
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
        stride_size = wp2.stride;
        if numel(stride_size) == 1
            stride_size = [stride_size, stride_size];
        end
        pad_size = wp2.pad;
        if numel(pad_size) == 1
            pad_size = [pad_size, pad_size, pad_size, pad_size];
        end


        resource.weight = {[],[]};
        btmSize = bottomSizes{1};
        topSizes = {[ceil([(btmSize(1)+2*pad_size(1)-kernel_size(1))/stride_size(1)+1, (btmSize(2)+2*pad_size(2)-kernel_size(2))/stride_size(2)+1]), wp2.num_output, btmSize(4)]};


        if wp1.enable_terms(1)
            resource.weight{1} = wp1.generator{1}([kernel_size(1), kernel_size(2), bottomSizes{1}(3), wp2.num_output], wp1.generator_param{1});
        end

        if wp1.enable_terms(2)
            resource.weight{2} = wp1.generator{2}([1, wp2.num_output], wp1.generator_param{2});
        end

        %return updated param
        param.weight_param = wp1;
        param.convolution_param = wp2;
    end


    function [outputBlob, weightUpdate] = forward(opts, l, weights, blob)
        outputBlob{1} = vl_nnconv(blob{1}, weights{1}, weights{2}, 'pad', l.convolution_param.pad, 'stride', l.convolution_param.stride);
        weightUpdate = {};
    end


    function [outputdzdx, outputdzdw] = backward(opts, l, weights, blob, dzdy)
        %numel(outputdzdx) = numel(blob), numel(outputdzdw) = numel(weights)
        [ outputdzdx{1}, outputdzdw{1}, outputdzdw{2} ]= ...
                         vl_nnconv(blob{1}, weights{1}, weights{2}, dzdy{1}, 'pad', l.convolution_param.pad, 'stride', l.convolution_param.stride);
    end

end