-- arg shifting
if arg[1] then
	for i = 0, #arg do arg[i-1] = arg[i] end
	arg[#arg] = nil
	dofile(arg[0])
end

