package.path = '/workspace/zdc/lua/?.lua;/workspace/zdc/lib/lua/?.lua;'..package.path
package.path = '/workspace/zdc/lua/zsvc/?.lua;/workspace/zdc/lua/zai/?.lua;/workspace/zdc/?.lua;'..package.path
package.cpath = '/workspace/zdc/lib/mac64/?.so;'..package.cpath

local rs232 = require("luars232")
local bit = require("bit")
local band,rshift,bxor = bit.band,bit.rshift,bit.bxor
-- Linux
-- port_name = "/dev/ttyS0"

-- (Open)BSD
port_name = "/dev/tty.usbserial-A50285BI"

-- Windows
-- port_name = "COM1"

local out = io.stderr

-- open port
local e, p = rs232.open(port_name)
if e ~= rs232.RS232_ERR_NOERROR then
	-- handle error
	out:write(string.format("can't open serial port '%s', error: '%s'\n",
			port_name, rs232.error_tostring(e)))
	return
end

-- set port settings
assert(p:set_baud_rate(rs232.RS232_BAUD_115200) == rs232.RS232_ERR_NOERROR)
assert(p:set_data_bits(rs232.RS232_DATA_8) == rs232.RS232_ERR_NOERROR)
assert(p:set_parity(rs232.RS232_PARITY_EVEN) == rs232.RS232_ERR_NOERROR)
assert(p:set_stop_bits(rs232.RS232_STOP_1) == rs232.RS232_ERR_NOERROR)
assert(p:set_flow_control(rs232.RS232_FLOW_OFF)  == rs232.RS232_ERR_NOERROR)

out:write(string.format("OK, port open with values '%s'\n", tostring(p)))
print(p:read(1,100))

local stb=
{
	support_cmd={},
	blksize=128,--for stm8, stm32 is 256
 	address=0xa0,
	-- address=0x008000
}

local cmd=
{
	O=string.char(0x00),
	SYN=string.char(0x7f),
	GET=string.char(0x00)..string.char(0xff),
	READ=string.char(0x11)..string.char(0xee),
	ERASE=string.char(0x43)..string.char(0xbc),
	WRITE=string.char(0x31)..string.char(0xce)
}

local rsp=
{
	ack=string.char(0x79),
	nack=string.char(0x1f),
	busy=string.char(0xaa),
}

local function tohex(s)
	if type(s) == 'string' then
		return string.gsub(s,'.',function(c)
			return string.format('%02x',c:byte())
		end)
	elseif type(s) == 'number' then
		return string.format('%02x',s)
	end
end

local function tostr(d)
	local s=''
	for _,v in ipairs(d) do
		s=s..string.char(v)
	end
	return s
end

local function checksum(d,init)
	local xor=init or 0x00
	if type(d) == 'table' then
		for k,v in ipairs(d) do
			xor=bxor(xor,v)
		end
	elseif type(d) == 'string' then
		string.gsub(d,'.',function(c)
			xor=bxor(xor,c:byte())
		end)
	else
		return nil
	end
	return xor
end

local function sleep(t)
	os.execute('sleep '..t)
end

local function wait_reply()
	local err, msg=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(msg)
	return true, msg
end

local timeout=100
local function synch()
	p:write(cmd.SYN)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'synch rejected'
	end
	return true, ack
end

local function get()
	p:write(cmd.GET)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '1'
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'get rejected'
	end
	local err,sz=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '2'
	end
	p:write(sz)
	sz=string.byte(sz)
	local d={}
	for i=1,sz+1 do
		err,msg=p:read(1,timeout)
		if err ~= rs232.RS232_ERR_NOERROR then
			return false, err
		end
		d[#d+1]=msg
		p:write(msg)
	end
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'ops rejected'
	end
	local v=string.byte(d[1])
	stb.ver=band(rshift(v,4),0xff)..'.'..band(v,0x0f)
	for i=2,sz+1 do
		stb.support_cmd[#stb.support_cmd+1]=string.byte(d[i])
	end
	return true
end

local function write(address,data)
	p:write(cmd.WRITE)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack, 'write rejected'
	end
	local d={}
	d[1]=band(rshift(address,24),0xff)
	d[2]=band(rshift(address,16),0xff)
	d[3]=band(rshift(address,8),0xff)
	d[4]=band(address,0xff)
	d[5]=checksum(d)
	p:write(tostr(d))
	print(tohex(tostr(d)))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack, 'address rejected'
	end
	p:write(string.char(#data-1))
	p:write(data)
	p:write(string.char(checksum(data,#data-1)))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'data rejected'
	end
	return true
end

local function erase(sectorCodes)
	p:write(cmd.ERASE)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'erase 1 rejected'
	end
	local d={}
	if sectorCodes then
		d[#d+1]=#sectorCodes-1
		for _,v in ipairs(sectorCodes) do
			d[#d+1]=v
		end
		d[#d+1]=checksum(sectorCodes,#sectorCodes-1)
	else
		d[#d+1]=0xff
		d[#d+1]=0x00
	end
	p:write(tostr(d))
	print(tohex(tostr(d)))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'erase 2 rejected'
	end
	return true
end

local function loadfile(filename)
	if not filename then
		return false, 'filename not exit'
	end
	local address=stb.address
	local f=io.open(filename,'r')
	while true do
		print('blk:'..tohex(address))
		local blk=f:read(stb.blksize)
		if not blk then
			break
		end
		local r,code,msg = write(address,blk,blk:len())
		if not r then
			f:close()
			return false,code,msg
		end
		address=address+blk:len()
	end
	f:close()
	return true
end

if true then
do
	local r, code, msg
	repeat
		sleep(1)
		r, code, msg=synch()
		print('synch',r,tohex(code),msg)
	until ((code == rsp.ack) or (code == rsp.nack))
	print('synch,success')

	local r, code, msg=get()
	print(r,tohex(code),msg)
	if r then
		print('stm8,version:'..stb.ver)
		print('supported cmd:')
		for _,v in ipairs(stb.support_cmd) do
			print(tohex(v))
		end
		-- local r, code, msg=loadfile('./test.s19')
	 	local r, code, msg=erase({0x03})
	 	print(r,tohex(code),msg)
	 -- 	for i=0,0x20 do
		--  	local r, code, msg=erase({i})
		-- 	print(r,tohex(code),msg)
		-- end
	end
end
else
	local address=stb.address
	local d={}
	d[1]=band(rshift(address,24),0xff)
	d[2]=band(rshift(address,16),0xff)
	d[3]=band(rshift(address,8),0xff)
	d[4]=band(address,0xff)
	d[5]=checksum(d)
	p:write(rsp.ack)
	print(p:write(tostr(d)))
	print(tohex(tostr(d)))
	print(p:read(20,100))
	-- local d={}
	-- local sectorCodes={0x01,0x02,0x03}
	-- d[#d+1]=#sectorCodes-1
	-- for _,v in ipairs(sectorCodes) do
	-- 	d[#d+1]=v
	-- end
	-- d[#d+1]=checksum(sectorCodes,#sectorCodes-1)
	-- print(p:write(tostr(d)))
	-- print(tohex(tostr(d)))
end
assert(p:close() == rs232.RS232_ERR_NOERROR)