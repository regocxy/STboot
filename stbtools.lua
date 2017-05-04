_M=_M or {}

package.path = '/workspace/zdc/lua/?.lua;/workspace/zdc/lib/lua/?.lua;'..package.path
package.path = '/workspace/zdc/lua/zsvc/?.lua;/workspace/zdc/lua/zai/?.lua;/workspace/zdc/?.lua;'..package.path
package.cpath = '/workspace/zdc/lib/mac64/?.so;'..package.cpath

local band=require('bit').band

local function checksum(s)
	local cks=0
	s:gsub('..',function(hex)
		cks=cks+tonumber(hex,16)
	end)
	return 0xff-band(cks,0xff)
end

local function hex_to_bin(hex)
  return hex:gsub('..', function(hexval)
    return string.char(tonumber(hexval, 16))
  end)
end

local function tohex(s)
	if type(s) == 'string' then
		return string.gsub(s,'.',function(c)
			return string.format('%02x',c:byte())
		end)
	elseif type(s) == 'number' then
		return string.format('%x',s)
	else
		return nil,'params invalid'
	end
end

local function tostr(tbl)
	if type(tbl) == 'table' then
		local s=''
		for _,v in ipairs(tbl) do
			s=s..string.char(v)
		end
		return s
	else
		return nil, 'input invalid'
	end
end

local function s19_to_tbl(filename)
	if not filename then
		return nil,'filename not exit'
	end
	local tbl={}
	local f,msg=io.open(filename,'r')
	if not f then
		return nil,msg
	end
	for line in f:lines() do
		if line:sub(-1,-1)==string.char(13) then
			line=line:sub(1,-2)
		end
		tbl[#tbl+1]={
			head=line:sub(1,2),
			len=tonumber(line:sub(3,4),16)-3,
			addr=tonumber(line:sub(5,8),16),
			data=hex_to_bin(line:sub(9,-3))
		}
		local cks=tonumber(line:sub(-2,-1),16)
		if checksum(line:sub(3,-3)) ~= cks then
			f:close()
			return nil,'line data checksum invalid'
		end
	end
	f:close()
	return tbl
end

local function probe()
	local record,msg=s19_to_tbl('./E_W_ROUTINEs_32K_ver_1.3.s19')
	local f=io.open("./log",'w')
	if record then
		for _,v in ipairs(record) do
			print(tohex(v.addr), v.data)
			if v.head=='S1' then
				f:write(v.data)
			end
		end
	else
		print(record,msg)
	end
	f:close()
end

_M.s19_to_tbl=s19_to_tbl
_M.tohex=tohex
_M.tostr=tostr
return _M

