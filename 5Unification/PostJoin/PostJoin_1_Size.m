src_dir = 'C:\dev\datasets\conn\main_dataset\ac3train\';
dice_string = 'diced_xy=512_z=32_xyOv=128_zOv=12_dwnSmp=1';
result_name = 'res_from_sept_14_seg60_scf095_PF';
%result_name = 'res_from_sept_14_seg60_scf0975_PF';
nresult = 1;

if exist('src_vol', 'var')
    fprintf(1, 'Reusing volumes.\n');
else
    
    %Load src images
    fprintf(1, 'Loading images.\n');
    src_folder = fullfile(src_dir, 'input_images');
    src_files = [ dir(fullfile(src_folder, '*.tif')); ...
        dir(fullfile(src_folder, '*.png')) ];
    src_files = sort({src_files.name});
    
    src_info = imfinfo(fullfile(src_folder, src_files{1}));
    % Assume all images are the same size
    src_vol = zeros(src_info.Height, src_info.Width, length(src_files), 'uint8');
    prob_vol = zeros(src_info.Height, src_info.Width, length(src_files), 'double');
    seg_vol = zeros(src_info.Height, src_info.Width, length(src_files), 'uint32');
    
    for zi = 1:length(src_files)
        img = imread(fullfile(src_folder, src_files{zi}));
        if(size(img, 3)) == 3
            %Ignore color
            src_vol(:,:,zi) = uint32(img(:,:,1));
        else
            src_vol(:,:,zi) = img;
        end
    end
    
    %Load probabilities
    fprintf(1, 'Loading probabilities.\n');
    prob_folder = fullfile(src_dir, 'forest_prob');
    prob_files = [ dir(fullfile(prob_folder, '*.mat')) ];
    prob_files = sort({prob_files.name});
    
    for zi = 1:length(prob_files)
        load_img = load(fullfile(prob_folder, prob_files{zi}), 'imProb');
        prob_vol(:,:,zi) = load_img.imProb;
    end
    clear load_img;
    
    
    %Load segmentation
    fprintf(1, 'Loading segmentation.\n');
    seg_folder = fullfile(src_dir, dice_string, result_name, ['FS=' num2str(nresult)], 'stitched', 'labels');
    seg_files = [ dir(fullfile(seg_folder, '*.tif')); ...
        dir(fullfile(seg_folder, '*.png')) ];
    seg_files = sort({seg_files.name});
    
    % Load seg data
    for zi = 1:length(seg_files)
        img = imread(fullfile(seg_folder, seg_files{zi}));
        if(size(img, 3)) == 3
            %Map 8-bit color image to 32 bit
            seg_vol(:,:,zi) = uint32(img(:,:,1));
            seg_vol(:,:,zi) = seg_vol(:,:,zi) + uint32(img(:,:,2)) * 2^8;
            seg_vol(:,:,zi) = seg_vol(:,:,zi) + uint32(img(:,:,3)) * 2^16;
        else
            seg_vol(:,:,zi) = img;
        end
    end
    
    %Compress labels
    [~, ~, seg_index] = unique(seg_vol(:));
    seg_vol = reshape(uint32(seg_index)-1, size(seg_vol));
    
    %Grow regions until there are no more black lines
    borders = seg_vol==0;
    dnum = 0;
    disk1 = strel('disk', 1, 4);
    while any(borders(:))
        dvol = imdilate(seg_vol, disk1);
        seg_vol(borders) = dvol(borders);
        borders = seg_vol==0;
        
        dnum = dnum + 1;
        fprintf(1, 'Growing regions: %d.\n', dnum);
    end
end

sz = size(seg_vol);
segs = double(max(seg_vol(:)));

fprintf(1, 'Calculating adjicency.\n');
[borders adj conn npix dist valid avedist] = makeConn2(seg_vol, prob_vol);

adj_bak = adj;
conn_bak = conn;
npix_bak = npix;
dist_bak = dist;
valid_bak = valid;
avedist_bak = avedist;

segments = seg_vol;

%fprintf(1, 'Calculating tree.\n');
%tree = mst(avedist);

%Calculate segment sizes
fprintf(1, 'Calculating segment sizes.\n');
seg_stats = regionprops(seg_vol, 'Area', 'PixelIdxList');

segsizes_i = [seg_stats.Area];

%Now join up segments
fprintf(1, 'Joining segments.\n');
validsegs = segsizes_i > 0;
for minsegsize = [1000 2500 5000 10000 15000 20000 25000];
    %segoi = 1;
    fprintf(1,'Joining segments up to size %d.\n', minsegsize);
    %Blank out anything unconnected
    blankout = false(size(seg_vol));
    blanki = 0;
    
    becomes = zeros(1,segs);
    becomestest = 1:segs;
    joinphase = 0;
    
    brdRewrite = zeros(size(borders));
    
    while joinphase < 10 && any(segsizes_i(validsegs) < minsegsize)
        
        joinphase = joinphase + 1;
        
        %find all small nodes
        [segsizes_o segorder] = sort(segsizes_i);
        
        joini = 0;
        for segi = segorder
            if validsegs(segi) && segsizes_i(segi) > 0 && segsizes_i(segi) < minsegsize
                %Join this segment to its closest neighbour
                reach = find(conn(segi,:));
                [mindist minr] = min(avedist(segi,reach));
                neighbour = reach(minr);
                becomes(segi) = neighbour;
                becomes(becomes==segi) = neighbour;
                if ~validsegs(neighbour)
                    neighbour = becomes(neighbour);
                    if neighbour == 0
                        fprintf(1, 'Warning - invalid neighbour.\n');
                        blankout(seg_vol == segi) = true;
                        blanki = blanki + 1;
                        validsegs(segi) = false;
                    else
                        fprintf(1, 'Joining neighbour through previous join.\n');
                        becomes(segi) = neighbour;
                        becomes(becomes==segi) = neighbour;
                    end
                end
                if any(becomes==becomestest)
                    fprintf(1, 'Warning - loop created.\n');
                end
                
                segsizes_i(neighbour) = segsizes_i(neighbour) + segsizes_i(segi);
                
                %Don't join the neighbour to itself
                conn(segi,neighbour) = 0;
                npix(segi,neighbour) = 0;
                dist(segi,neighbour) = 0;
                
                %Join to other connections
                update = find(conn(segi,:));
                conn(neighbour,update) = 1;
                npix(neighbour,update) = npix(neighbour,update) + npix(segi,update);
                dist(neighbour,update) = dist(neighbour,update) + dist(segi,update);
                avedist(neighbour,update) = dist(neighbour,update)./npix(neighbour,update);
                
                conn(update,neighbour) = conn(neighbour,update);
                npix(update,neighbour) = npix(neighbour,update);
                dist(update,neighbour) = dist(neighbour,update);
                avedist(update,neighbour) = avedist(neighbour,update);
                
                %disconnect
                %(no need to update disconnected distances)
                conn(segi,update) = 0;
                conn(update,segi) = 0;
                conn(neighbour,segi) = 0;
                conn(segi,neighbour) = 0;
                
                validsegs(segi) = false;
                
                %fprintf(1, 'dist = %1.6f : Joined segment %d (size = %1.2f) to %d (size = %1.2f).\n', ...
                %    avedist(segi, neighbour), segi, segsizes_i(segi), neighbour, segsizes_i(neighbour));
                
                %write border to the output segments
                %joinborder = (any(adj == segi,2) & any(adj == neighbour,2)) | brdRewrite == segi;
                %brdRewrite(joinborder) = neighbour;
                
                %Modify the adjacency matrix
                adj(adj==segi) = neighbour;
                
                joini = joini + 1;
                
                if mod(joini, 100) == 0
                    fprintf(1, 'Joined %d segments. Up to size %d.\n', ...
                        joini, segsizes_i(segi));
                end
            end
        end
        
        fprintf(1, 'Phase %d. Joined %d segments.\n', joinphase, joini);
        
    end
    
    %brdIndex = brdRewrite ~= 0;
    %segments(borders(brdIndex)) = brdRewrite(brdIndex);
    
    segments(blankout) = 0;
    fprintf(1, 'Blanked out %d unreachable islands.\n', blanki);
    
    rewrites = unique(becomes(becomes > 0));
    fprintf(1, 'Joining %d segments to %d supersegments.\n', joini, length(rewrites));
    
    if ~isempty(rewrites)
        for newseg = rewrites
            oldsegs = find(becomes==newseg);
            oldindex = false(sz);
            for oldsegi = oldsegs
                oldindex(seg_vol == oldsegi) = true;
            end
            segments(oldindex) = newseg;
        end
    end
    
    close all;
    quickshowdualhsv_demo(src_vol, segments)
    
    disp('Cleaning...');
    cleanseg = clean1(segments);
    close all;
    quickshowdualhsv_demo(src_vol, cleanseg)
    
    save(sprintf('PostJoin_%s_Size=%d.mat', result_name, minsegsize), 'segments', 'cleanseg');
    
    %prepare for more joining
    seg_vol = segments;
    
end