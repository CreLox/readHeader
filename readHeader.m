% FileHeaderStruct = readHeader(FormatExplanationTable, FilePath(OPTIONAL),
% DefaultFileExtension(OPTIONAL))
function FileHeaderStruct = readHeader(FormatExplanationTable, FilePath, ...
    DefaultFileExtension)
    %% Columns in FormatExplanationTable (each row is for one property)
    % This column stores the name of a property.
    PropertyNameIdx      = 1;
    % This column stores the (starting BYTE - 1) position of the property.
    % (e.g. if a property of the "uint32" type spans 4 bytes, #17-#20, the
    % (starting BYTE - 1) position of this property will be 16.)
    % If the (starting BYTE - 1) position is not supplied/NaN, the current
    % position ftell(FID) will be used.
    StartingByteIdx      = 2;
    % This column stores the data type, which determines the byte length of
    % the property.
    TypeIdx              = 3;
    % (OPTIONAL) This column stores any (simple) data handling method
    % utilizing a MATLAB function handle.
    TranslationMethodIdx = 4;
    
    %% Robust inputs
    % FormatExplanationTable can either be a MATLAB table class object or
    % the path to the file containing the table.
    if ~istable(FormatExplanationTable)
        FormatExplanationTable = readtable(FormatExplanationTable, ...
            'Delimiter', '\t', 'ReadVariableNames', false, 'TextType', 'string');
    end
    % if FilePath is not supplied, a file seletion window will pop up to
    % allow user to select the file to be read.
    if ~exist('FilePath', 'var') || isempty(FilePath)
        if ~exist('DefaultFileExtension', 'var') || isempty(DefaultFileExtension)
            [Filename, Path] = uigetfile('*.*');
        else
            [Filename, Path] = uigetfile(DefaultFileExtension);
        end
        FilePath = strcat(Path, Filename);
    end
    
    %% Main
    FID = fopen(FilePath);
    FileHeaderStruct = struct;
    for i = 1 : size(FormatExplanationTable, 1)
        if isnumeric(FormatExplanationTable{i, StartingByteIdx}) && ...
                ~isnan(FormatExplanationTable{i, StartingByteIdx})
            fseek(FID, FormatExplanationTable{i, StartingByteIdx}, 'bof');
        end
        if (size(FormatExplanationTable, 2) == 3) || ...
                strcmp(FormatExplanationTable{i, TranslationMethodIdx}, "") || ...
                ismissing(FormatExplanationTable{i, TranslationMethodIdx})
            % If TranslationMethod is not supplied, type coercion is the default.
            Translate = str2func(FormatExplanationTable{i, TypeIdx});
        else
            Translate = str2func(FormatExplanationTable{i, TranslationMethodIdx});
        end
        FileHeaderStruct.(FormatExplanationTable{i, PropertyNameIdx}) = ...
            Translate(fread(FID, 1, FormatExplanationTable{i, TypeIdx}));
    end
    FileHeaderStruct.FilePath = FilePath;
    fclose(FID);
end
