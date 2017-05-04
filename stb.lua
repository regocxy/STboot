package.path = '/workspace/zdc/lua/?.lua;/workspace/zdc/lib/lua/?.lua;'..package.path
package.path = '/workspace/zdc/lua/zsvc/?.lua;/workspace/zdc/lua/zai/?.lua;/workspace/zdc/?.lua;'..package.path
package.cpath = '/workspace/zdc/lib/mac64/?.so;'..package.cpath

local rs232 = require("luars232")
local tools = require('stbtools')
local bit = require("bit")

local s19_to_tbl,tohex,tostr= tools.s19_to_tbl,tools.tohex,tools.tostr
local band,rshift,bxor = bit.band,bit.rshift,bit.bxor

local stb=
{
	support_cmd={},
	blksize=128,--for stm8, stm32 is 256
 	start_address=0x8000,
 	timeout=100,
 	port_name='/dev/tty.usbserial-A50285BI'
}

local out = io.stderr

-- open port
local e, p = rs232.open(stb.port_name)
if e ~= rs232.RS232_ERR_NOERROR then
	-- handle error
	out:write(string.format("can't open serial port '%s', error: '%s'\n",
			stb.port_name, rs232.error_tostring(e)))
	return
end

-- set port settings
assert(p:set_baud_rate(rs232.RS232_BAUD_115200) == rs232.RS232_ERR_NOERROR)
assert(p:set_data_bits(rs232.RS232_DATA_8) == rs232.RS232_ERR_NOERROR)
assert(p:set_parity(rs232.RS232_PARITY_NONE) == rs232.RS232_ERR_NOERROR)
assert(p:set_stop_bits(rs232.RS232_STOP_1) == rs232.RS232_ERR_NOERROR)
assert(p:set_flow_control(rs232.RS232_FLOW_OFF)  == rs232.RS232_ERR_NOERROR)

out:write(string.format("OK, port open with values '%s'\n", tostring(p)))
print(p:read(1,100))

local cmd=
{
	O=string.char(0x00),
	SYN=string.char(0x7f),
	GET=string.char(0x00)..string.char(0xff),
	READ=string.char(0x11)..string.char(0xee),
	ERASE=string.char(0x43)..string.char(0xbc),
	WRITE=string.char(0x31)..string.char(0xce),
	GO=string.char(0x21)..string.char(0xde)
}

local rsp=
{
	ack=string.char(0x79),
	nack=string.char(0x1f),
	busy=string.char(0xaa),
}

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

local function read(address,n)
	p:write(cmd.READ)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '1'
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
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '2'
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack, 'data rejected'
	end
	d={}
	if n and n<=0xff then
		d[1]=n
		d[2]=checksum(n)
	else
		d[1]=0x01
		d[2]=0xfe
	end
	p:write(tostr(d))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '3'
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack, 'data rejected'
	end
	local err, v=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '4'
	end
	p:write(v)
	local err, v=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '5'
	end
	p:write(v)
	return true, v
end

local function comm(s)
	p:write(s)
	-- print(tohex(s))
end

local function write(address,data,ex)
	local timeout=ex or stb.timeout
	comm(cmd.WRITE)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '1'
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
	comm(tostr(d))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '2'
	end
	comm(ack)
	if ack ~= rsp.ack then
		return false, ack, 'address rejected'
	end
	comm(string.char(#data-1))
	comm(data)
	comm(string.char(checksum(data,#data-1)))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '3'
	end
	comm(ack)
	if ack ~= rsp.ack then
		return false, ack, 'data rejected'
	end
	return true
end

local function erase(sectorCodes)
	p:write(cmd.ERASE)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '1'
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
	sleep(1)
	local err, ack=p:read(1,100)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '2'
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'erase 2 rejected'
	end
	return true
end

local function go(address)
	p:write(cmd.GO)
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err, '1'
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack,'erase 1 rejected'
	end
	local d={}
	d[1]=band(rshift(address,24),0xff)
	d[2]=band(rshift(address,16),0xff)
	d[3]=band(rshift(address,8),0xff)
	d[4]=band(address,0xff)
	d[5]=checksum(d)
	p:write(tostr(d))
	local err, ack=p:read(1,timeout)
	if err ~= rs232.RS232_ERR_NOERROR then
		return false, err
	end
	p:write(ack)
	if ack ~= rsp.ack then
		return false, ack, 'address rejected'
	end
	return true
end

local function loadfile(filename)
	local record,msg=s19_to_tbl(filename)
	if not record then
		return false,msg
	end
	table.sort(record,function(a,b)
		return a.addr < b.addr
	end)
	local s=''
	for k,v in pairs(record) do
		print(k,#v.data,tohex(v.addr))
		if v.head == 'S1' then
			s=s..v.data
		end
	end
	local l=0
	local sz=#s
	local addr = record[2].addr
	while l<sz do
		local d=s:sub(l+1,l+128)
		print(tohex(addr+l),write(addr+l,d,500))
		l=l+#d
	end
	print(tohex(addr+l))
	return true
end 

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
		print('-----------------------')
		print('stm8,version:'..stb.ver)
		print('supported cmd:')
		for _,v in ipairs(stb.support_cmd) do
			print(tohex(v))
		end
		print('-----------------------')
		local r,msg=loadfile('./res/E_W_ROUTINEs_32K_ver_1.3.s19')
		print(r,msg)
		if r then
			local r,code,msg=read(0x4000)
			print('read',r,code,msg)
			if r then
				-- print(erase())
				print(loadfile('./res/test.s19'))
				go(stb.start_address)
			end
		end
	end
end

assert(p:close() == rs232.RS232_ERR_NOERROR)