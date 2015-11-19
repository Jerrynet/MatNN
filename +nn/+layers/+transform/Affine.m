classdef Affine < handle

    % Default parameters
    properties (SetAccess = protected, Transient)
        default_affine_param = {
            'sampler' 'bilinear' ... % currently only support bilinear interpolation
            'showDebugWindow' false ...
        };
    end

    % intermediate savings (computed values, recomputed every time)
    properties (Access = protected)
        forwardHandle;
        backwardHandle;
        count;
        MaxThreadsPerBlock = 256;
    end


    methods
        function v = propertyDevice(obj)
            v = obj.propertyDevice@nn.layers.template.BaseLayer();
            v.count = 0;
            v.forwardHandle = 1;
            v.backwardHandle  = 1;
        end

        function out = f(obj, in, affineMatrix)
            out = in.*0;
            s = nn.utils.size4D(in);
            len = prod(s);
            obj.forwardHandle.GridSize = ceil( len/obj.MaxThreadsPerBlock );
            out = feval(obj.forwardHandle, in, s, affineMatrix, len, out);
        end
        function [in_diff, affine_diff] = b(obj, in, affineMatrix, out, out_diff)
            in_diff = out_diff.*0;
            s = nn.utils.size4D(out_diff);
            len = prod(s);
            affine_diff = affineMatrix.*0;
            obj.backwardHandle.GridSize = ceil( len/obj.MaxThreadsPerBlock );
            [in_diff, affine_diff] = feval(obj.backwardHandle, in, s, affineMatrix, len, out, out_diff, in_diff, affine_diff);
            %[bottom_diff{1}, bottom_diff{2}] = feval(ab, bottom{1}, s, bottom{2}, len, top{1}, top_diff{1}, bottom_diff{1}, bottom_diff{2});
            % should in_diff divivded by pixelnumber?
        end
        function out = gf(obj, varargin)
            out = obj.f(varargin{:});
        end
        function in_diff = gb(obj, varargin)
            in_diff = obj.b(varargin{:});
        end

        % Forward function for training/testing routines
        function [top, weights, misc] = forward(obj, opts, top, bottom, weights, misc)
            if opts.gpuMode
                top{1} = obj.f(bottom{1}, bottom{2});
                if obj.params.affine.showDebugWindow
                    if mod(obj.count, 20) == 0
                        t = gather(bottom{2}(:,:,:,1));
                        o1 = trans(t, [1,1]      , s(1:2));
                        o2 = trans(t, [s(1),1]   , s(1:2));
                        o3 = trans(t, [s(1),s(2)], s(1:2));
                        o4 = trans(t, [1,s(2)]   , s(1:2));
                        ox = [o1(2),o2(2),o3(2),o4(2)];
                        oy = [o1(1),o2(1),o3(1),o4(1)];

                        subplot(1,2,1), imshow(gather(bottom{1}(:,:,:,1)), []), ...
                                        line(ox(1:2), oy(1:2), 'LineWidth',4,'Color','r'), ...
                                        line(ox(2:3), oy(2:3), 'LineWidth',4,'Color','g'), ...
                                        line(ox(3:4), oy(3:4), 'LineWidth',4,'Color','b'), ...
                                        line(ox([4,1]), oy([4,1]), 'LineWidth',4,'Color','y');
                        set(gca,'Clipping','off');
                        subplot(1,2,2), imshow(gather(top{1}(:,:,:,1)), []);
                        drawnow;
                        obj.count = 0;
                    end
                    obj.count = obj.count+1;
                end
            else
                error('Affine Layer : only support gpu mode currently.');
            end
            function o = trans(a,o,s) % p = [y,x], s = [h,w]
                p = 2*((o./s)-0.5);
                o(2) = a(1)*p(2) + a(3)*p(1) + a(5);
                o(1) = a(2)*p(2) + a(4)*p(1) + a(6);
                o = (o./2+0.5).*s;
            end
        end
        % Backward function for training/testing routines
        function [bottom_diff, weights_diff, misc] = backward(obj, opts, top, bottom, weights, misc, top_diff, weights_diff)
            if opts.gpuMode
                bottom_diff{1} = obj.gb(bottom{1}, bottom{2}, top{1}, top_diff{1});
            else
                error('Affine Layer : only support gpu mode currently.');
            end
        end
        function [outSizes, resources] = setup(obj, opts, baseProperties, inSizes)
            [outSizes, resources] = obj.setup@nn.layers.template.BaseLayer(opts, baseProperties, inSizes);
            assert(numel(baseProperties.bottom)==2);
            assert(numel(baseProperties.top)==1);
            obj.createGPUFun();
        end
        function createGPUFun(obj, sampleSize)
            mf = fileparts(mfilename('fullpath'));
            ptxp = fullfile(mf, 'private', 'affine.ptx');
            cup = fullfile(mf, 'private', 'affine.cu');
            obj.forwardHandle = nn.utils.gpu.createHandle(prod(sampleSize), ptxp, cup, 'AffineForward');
            obj.backwardHandle = nn.utils.gpu.createHandle(prod(sampleSize), ptxp, cup, 'AffineBackward');
        end
    end
end