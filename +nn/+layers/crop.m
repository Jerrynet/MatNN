function o = crop(varargin)
%CROP Crop Large data to a smaller size
%  NOTICE:
%    bottom{1} is the desired blob need to be croped
%    bottom{2} provide the size to crop bottom{1}

o.name         = 'Crop';
o.generateLoss = false;
o.setup        = @setup;
o.forward      = @forward;
o.backward     = @backward;


default_crop_param = {
         'offset' [] ...  % A 2-element vector, indicates the offset of H,W to crop
                          % if set to [], means use the center position
};

    function [resource, topSizes, param] = setup(l, bottomSizes)
        % resource only have .weight
        % if you have other outputs you want to save or share
        % you can set its learning rate to zero to prevent update
        resource = {};

        if isfield(l, 'crop_param')
            wp = nn.utils.vararginHelper(default_crop_param, l.crop_param);
        else
            wp = nn.utils.vararginHelper(default_crop_param, default_crop_param);
        end

        assert(numel(l.bottom)==2);
        assert(numel(l.top)==1);

        HW1 = bottomSizes{1}(1:2);
        HW2 = bottomSizes{2}(1:2);

        % use smallest bottom size as top size
        if HW1(1) >= HW2(1) && HW1(2) >= HW1(2)
            topSizes = bottomSizes(2);
        else
            error('Crop Layer bottom size is wrong.');
        end
        
        %return updated param
        param.crop_param = wp;
    end


    function [top, weights, misc] = forward(opts, l, weights, misc, bottom, top)
        s = [1,1,1,1];
        sizeofBlob2 = size(bottom{2});%small
        sizeofBlob1 = size(bottom{1});%large
        s(1:numel(sizeofBlob2)) = sizeofBlob2;

        c = l.crop_param.offset;
        if isempty(c)
            c = -round((s(1:2) - sizeofBlob1(1:2))/2);% compatible with FCN's crop layer??
        end
        top{1} = bottom{1}(c(1)+1:c(1)+s(1), c(2)+1:c(2)+s(2), :, :);
    end


    function [bottom_diff, weights_diff, misc] = backward(opts, l, weights, misc, bottom, top, top_diff, weights_diff, weights_diff_isCumulate)
        s = [1,1,1,1];
        sizeofBlob2 = size(bottom{2});
        sizeofBlob1 = size(bottom{1});
        s(1:numel(sizeofBlob2)) = sizeofBlob2;

        c = l.crop_param.offset;
        if isempty(c)
            c = -round((s(1:2) - sizeofBlob1(1:2))/2);% compatible with FCN's crop layer??
        end
        bottom_diff{1} = bottom{1}*0; %use this trick if you dont want to use 'if opt.gpu ...'
        bottom_diff{1}(c(1)+1:c(1)+s(1), c(2)+1:c(2)+s(2), :, :) = top_diff{1};
        bottom_diff{2} = [];

    end

end