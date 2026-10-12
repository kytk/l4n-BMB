function tf = endsWith (str, pattern, varargin)
% tf = endsWith (str, pattern)
% tf = endsWith (str, pattern, "IgnoreCase", true)
%
% endsWith for Octave 6 (jammy's apt version), which does not have it
% (added in Octave 7). Used by HCP Pipelines' fMRIStats_SummaryCSV.m.
% str and pattern: a char row or a cell array of them. tf is true where an
% element of str ends with any of the patterns; logical, the size of str
% (a scalar for a char str).
% Put on the path by l4n-bmb's octaverc only when endsWith is missing.

  ignore_case = false;
  if (numel (varargin) == 2 && strcmpi (varargin{1}, "IgnoreCase"))
    ignore_case = logical (varargin{2});
  elseif (! isempty (varargin))
    error ("endsWith: usage: endsWith (str, pattern [, \"IgnoreCase\", tf])");
  endif

  if (ischar (str))
    str = {str};
  endif
  if (ischar (pattern))
    pattern = {pattern};
  endif
  if (! iscellstr (str) || ! iscellstr (pattern))
    error ("endsWith: str and pattern must be char or cell arrays of char");
  endif
  if (ignore_case)
    str = lower (str);
    pattern = lower (pattern);
  endif

  tf = false (size (str));
  for i = 1:numel (str)
    s = str{i};
    for j = 1:numel (pattern)
      p = pattern{j};
      if (numel (p) <= numel (s) && strcmp (s(end-numel (p)+1:end), p))
        tf(i) = true;
        break;
      endif
    endfor
  endfor
endfunction
