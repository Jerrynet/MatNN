classdef Dropout < nn.layers.template.BaseLayer

    % Default parameters
    properties (SetAccess = protected, Transient)
        default_dropout_param = {
                    'name' {''}      ...  %empty names means use autogenerated name
            'enable_terms' true      ...
                    'rate' 0.5       ...
        };
    end

    methods
        function out = f(obj, in, mask)
            out = in.*mask;
        end
        function in_diff = b(obj, out_diff, mask)
            in_diff = out_diff.*mask;
        end
        function forward(obj, nnObj, l, opts, data, net)
            tmp = net.weightsIsMisc(l.weights);
            miscInd = l.weights(tmp);
            btm = data.val{l.bottom(1)};

            p = obj.params.dropout;
            if opts.disableDropout || ~p.enable_terms
                top = btm;
            elseif opts.freezeDropout && numel(btm) == numel(net.weights{miscInd})
                top = btm.*net.weights{miscInd};
            else
                if opts.gpuMode
                    mask = single(1 / (1 - p.rate)) .* (gpuArray.rand(size(btm),'single') >= p.rate);
                    top = btm .* mask;
                else
                    mask = single(1 / (1 - p.rate)) .* (rand(size(btm),'single') >= p.rate);
                    top = btm .* mask;
                end
                net.weights{miscInd} = mask;
            end
            data.val{l.top} = top;
        end
        function backward(obj, nnObj, l, opts, data, net)
            tmp = net.weightsIsMisc(l.weights);
            miscInd = l.weights(tmp);

            if opts.disableDropout || ~obj.params.dropout.enable_terms
                bottom_diff = data.diff{l.top};
            else
                bottom_diff = data.diff{l.top} .* net.weights{miscInd};
            end
            nn.utils.accumulateData(opts, data, l, bottom_diff);
        end
        function resources = createResources(obj, opts, l, inSizes, varargin)
            p = obj.params.dropout;
            if p.enable_terms
                scale = single(1 / (1 - p.rate)) ;
                resources.misc{1} = scale.* single(rand(inSizes{1}) >= p.rate);
            else
                resources = {};
            end
        end
        function setParams(obj, l)
            obj.setParams@nn.layers.template.BaseLayer(l);
            miscParam = obj.params.dropout;
            miscParam.name = {''};
            miscParam.enable_terms = true;
            miscParam.learningRate = 0;
            miscParam.weightDecay  = 0;
            obj.params.misc = miscParam;
        end
        function [outSizes, resources] = setup(obj, opts, l, inSizes, varargin)
            [outSizes, resources] = obj.setup@nn.layers.template.BaseLayer(opts, l, inSizes, varargin{:});
            assert(numel(l.bottom)==1);
            assert(numel(l.top)==1);

        end

    end
end