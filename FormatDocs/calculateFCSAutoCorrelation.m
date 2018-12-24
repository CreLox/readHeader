% [LagInSeconds, FCSAC, Filename] =
% calculateFCSAutoCorrelation(SegmentLengthInSeconds, MinLagInSeconds,
% MaxLagInSeconds, LagIntervalInSeconds)
% (A file selection UI window will pop up to allow the user to select a
% .fcs file)
% Note: 1. 'LagIntervalInSeconds' is only needed when calculating the
% "intensity" trace from macro time data under the time-tagged
% (time-resolved) acquisition mode. Under the count mode, it is always
% set to 1 / SampleFrequency.
% 2. Data are divided into segments of length 'SegmentLengthInSeconds' to
% alleviate signal drifting, as in FCS the auto-covariance is normalized by
% the squared mean. The first segment is ignored as severe photobleaching
% and system instability are often observed at the beginning of data
% acquisition. The auto-correlation at a certain time lag is the average of
% values calculated from all other segments.
% 3. Make sure that 'MaxLagInSeconds' << 'SegmentLengthInSeconds';
% otherwise, segmenting will significantly reduce the number of valid pairs
% of time points.
% 4. Please put this .m file and AlbaV5FCSFileFormat.txt under the same
% folder in MATLAB search paths.
% 5. Currently this function is supposed to only handle .fcs files
% containing a single trace.
function [LagInSeconds, FCSAC, Filename] = calculateFCSAutoCorrelation(...
    SegmentLengthInSeconds, MinLagInSeconds, MaxLagInSeconds, ...
    LagIntervalInSeconds)
    %% Parameter setting/read the header
    FCSHeader = readHeader(strcat(fileparts(mfilename('fullpath')), ...
        filesep, 'AlbaV5FCSFileFormat.txt'), [], '.fcs');
    [~, Filename, ~] = fileparts(FCSHeader.FilePath);
    if (FCSHeader.ChannelNumber > 1) || ...
        (FCSHeader.PositionSeriesCount > 1) || ...
        (FCSHeader.TimeSeriesCount > 1)
        error('This .fcs file contains more than one trace!');
    end
    if (FCSHeader.AcquisitionMode == 0)
        % Count mode - LagIntervalInSeconds is always set to 1 /
        % FCSHeader.SampleFrequency
        LagIntervalInSeconds = 1 / FCSHeader.SampleFrequency;
    else
        % Time-tagged (time-resolved) mode
        if ~exist('LagIntervalInSeconds', 'var') || ...
            isempty(LagIntervalInSeconds)
            LagIntervalInSeconds = min(1e-5, 1 / FCSHeader.SampleFrequency);
        end
    end
    % The first segment is ignored as severe photobleaching/system
    % instability is often observed at the beginning of data acquisition.
    StartFromThisSegment = 2;
    
    %% Read the trace
    Trace = struct();
    fid = fopen(FCSHeader.FilePath, 'r');
    fseek(fid, FCSHeader.MacroTimeOffset, 'bof'); 
    Trace.Length = fread(fid, 1, 'uint64') / double(FCSHeader.BytesPerDatum);
    if (FCSHeader.BytesPerDatum == 2)
        Trace.Data = fread(fid, Trace.Length, 'uint16');
    else
        Trace.Data = fread(fid, Trace.Length, 'uint32');
    end
    
    %% Calculate ACF and mean
    SegmentsNumber = floor(FCSHeader.SampleTime / SegmentLengthInSeconds);
    ACF = zeros(SegmentsNumber - StartFromThisSegment + 1, length(...
        ceil(MinLagInSeconds / LagIntervalInSeconds) : ...
        floor(MaxLagInSeconds / LagIntervalInSeconds)));
    if (FCSHeader.AcquisitionMode == 0)
        % Count mode - Trace.Data represent detected photon counts within
        % intervals of length 1 / FCSHeader.SampleFrequency
        for i = StartFromThisSegment : SegmentsNumber
            TimeSeries = Trace.Data((SegmentLengthInSeconds / LagIntervalInSeconds * (i - 1) + 1) : ...
                (SegmentLengthInSeconds / LagIntervalInSeconds * i));            
           [~, ACF(i - StartFromThisSegment + 1, :)] = ...
               calculateDiscreteTimeSeriesStatistics(TimeSeries, ...
               ceil(MinLagInSeconds / LagIntervalInSeconds) : ...
               floor(MaxLagInSeconds / LagIntervalInSeconds));
        end
    else
        % Time-tagged (time-resolved) mode - Trace.Data represent macro
        % times of detected photons
        Trace.ArrivalTime = cumsum(Trace.Data) / FCSHeader.ClockFrequency;
        for i = StartFromThisSegment : SegmentsNumber
            TimeSeries = histcounts(Trace.ArrivalTime, ...
                SegmentLengthInSeconds * (i - 1) : LagIntervalInSeconds : SegmentLengthInSeconds * i);
            [~, ACF(i - StartFromThisSegment + 1, :)] = ...
                calculateDiscreteTimeSeriesStatistics(TimeSeries, ...
                ceil(MinLagInSeconds / LagIntervalInSeconds) : ...
                floor(MaxLagInSeconds / LagIntervalInSeconds));
        end
    end
    FCSAC = mean(ACF);
    LagInSeconds = (ceil(MinLagInSeconds / LagIntervalInSeconds) : ...
        floor(MaxLagInSeconds / LagIntervalInSeconds)) * ...
        LagIntervalInSeconds;
end

function [TimeSeriesMean, NormalizedAutoCovariance] = ...
    calculateDiscreteTimeSeriesStatistics(TimeSeries, LagArray)
    TimeSeries = double(TimeSeries);
    TimeSeriesMean = mean(TimeSeries);
    NormalizedTimeSeries = TimeSeries - TimeSeriesMean;
    
    NormalizedAutoCovariance = zeros(size(LagArray));
    for i = 1 : length(LagArray)
        NormalizedAutoCovariance(i) = mean(...
            NormalizedTimeSeries(LagArray(i) + 1 : end) ...
            .* NormalizedTimeSeries(1 : end - LagArray(i))) ./ ...
            (TimeSeriesMean ^ 2);
    end
end
