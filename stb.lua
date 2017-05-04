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
	timeout=100,
	blksize=128,--for stm8, stm32 is 256
 	start_address=0x8000,--for stm8
 	path_routine='./res/E_W_ROUTINEs_32K_ver_1.3.s19',
 	path_firmware='./res/test.s19',
 	port_name='/dev/tty.usbserial-A50285BI',
 	erase_en=false
}

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
	t=t/1000
	os.execute('sleep '..t)
end

local function comm(s,timeout,wait)
	local timeout=timeout or stb.timeout
	if not stb.p then
		return false, nil, 'uart is not open'
	end
	if s then
		stb.p:write(s)
		if wait then
			sleep(wait)
		end
		local err, ack=stb.p:read(1,timeout)
		if err ~= rs232.RS232_ERR_NOERROR then
			return false, err, 'rs232'
		end
		stb.p:write(ack)
		if ack ~= rsp.ack then
			return false, ack, 'ops rejected'
		end
		return true, ack
	else
		local err, msg=stb.p:read(1,timeout)
		if err ~= rs232.RS232_ERR_NOERROR then
			return false, err, 'rs232'
		end
		stb.p:write(msg)
		return true, msg
	end
end

local function synch(timeout)
	local r,code,msg=comm(cmd.SYN)
	if not r then
		return false, code, msg
	end
	return true, ack
end

local function get(timeout)
	local r,code,msg=comm(cmd.GET)
	if not r then
		return false, code, msg
	end
	r,code,msg=comm()
	if not r then
		return false, code, msg
	end
	local sz=string.byte(code)
	local d={}
	for i=1,sz+1 do
		r,code,msg=comm()
		if not r then
			return false, code, msg
		end
		d[#d+1]=code
	end
	r,code,msg=comm()
	if not r then
		return false, code, msg
	end
	local v=string.byte(d[1])
	stb.ver=band(rshift(v,4),0xff)..'.'..band(v,0x0f)
	for i=2,sz+1 do
		stb.support_cmd[#stb.support_cmd+1]=string.byte(d[i])
	end
	return true
end

local function read(address,n,timeout)
	local r,code,msg=comm(cmd.READ)
	if not r then
		return false, code, msg
	end
	local d={}
	d[1]=band(rshift(address,24),0xff)
	d[2]=band(rshift(address,16),0xff)
	d[3]=band(rshift(address,8),0xff)
	d[4]=band(address,0xff)
	d[5]=checksum(d)
	local r,code,msg=comm(tostr(d))
	if not r then
		return false, code, msg
	end
	d={}
	if n and n<=0xff then
		d[1]=n
		d[2]=checksum(n)
	else
		d[1]=0x01
		d[2]=0xfe
	end
	local r,code,msg=comm(tostr(d))
	if not r then
		return false, code, msg
	end
	local r,code,msg=comm()
	if not r then
		return false, code, msg
	end
	local r,code,msg=comm()
	if not r then
		return false, code, msg
	end
	return true, code
end

local function write(address,data,timeout)
	local r,code,msg=comm(cmd.WRITE,timeout)
	if not r then
		return false,code,msg
	end
	local d={}
	d[1]=band(rshift(address,24),0xff)
	d[2]=band(rshift(address,16),0xff)
	d[3]=band(rshift(address,8),0xff)
	d[4]=band(address,0xff)
	d[5]=checksum(d)
	r,code,msg=comm(tostr(d))
	if not r then
		return false,code,msg
	end
	local s=string.char(#data-1)
	s=s..data..string.char(checksum(data,#data-1))
	r,code,msg=comm(s,timeout)
	if not r then
		return false,code,msg
	end
	return true
end

local function erase(sectorCodes,timeout)
	local r,code,msg=comm(cmd.ERASE,timeout)
	if not r then
		return false,code,msg
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
	local r,code,msg=comm(tostr(d),100,1000)
	if not r then
		return false,code,msg
	end
	return true
end

local function go(address,timeout)
	local r,code,msg=comm(cmd.GO)
	if not r then
		return false,code,msg
	end
	local d={}
	d[1]=band(rshift(address,24),0xff)
	d[2]=band(rshift(address,16),0xff)
	d[3]=band(rshift(address,8),0xff)
	d[4]=band(address,0xff)
	d[5]=checksum(d)
	r,code,msg=comm(tostr(d))
	if not r then
		return false,code,msg
	end
	return true
end

local function loadfile(filename)
	local record,msg=s19_to_tbl(filename)
	if not record then
		return false, nil, msg
	end
	table.sort(record,function(a,b)
		return a.addr < b.addr
	end)
	local s=''
	for k,v in pairs(record) do
		if v.head == 'S1' then
			s=s..v.data
		end
	end
	local l=0
	local sz=#s
	local addr = record[2].addr 
	local r,code,msg
	while l<sz do
		local d=s:sub(l+1,l+stb.blksize)
		r,code,msg=write(addr+l,d,500)
		if not r then
			return r, code, smg
		end
		print(tohex(addr+l))
		l=l+#d
	end
	print(tohex(addr+l))
	return true
end 

local function init()
	if stb.p then
		stb.p:close()
	end
	local e, p = rs232.open(stb.port_name)
	if e ~= rs232.RS232_ERR_NOERROR then
		local err=string.format("can't open serial port '%s', error: '%s'\n",stb.port_name, rs232.error_tostring(e))
		return false,err
	end
	assert(p:set_baud_rate(rs232.RS232_BAUD_115200) == rs232.RS232_ERR_NOERROR)
	assert(p:set_data_bits(rs232.RS232_DATA_8) == rs232.RS232_ERR_NOERROR)
	assert(p:set_parity(rs232.RS232_PARITY_NONE) == rs232.RS232_ERR_NOERROR)
	assert(p:set_stop_bits(rs232.RS232_STOP_1) == rs232.RS232_ERR_NOERROR)
	assert(p:set_flow_control(rs232.RS232_FLOW_OFF)  == rs232.RS232_ERR_NOERROR)
	print(p:read(1,stb.timeout))
	stb.p=p
	return true,string.format("OK, port open with values '%s'\n", tostring(p))
end

local function close()
	assert(stb.p:close() == rs232.RS232_ERR_NOERROR)
	return true,'close'
end

do
	print(init())
	local r, code, msg
	repeat
		sleep(500)
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
		local r,msg=loadfile(stb.path_routine)
		print(r,msg)
		if r then
			local r,code,msg=read(0x4000)
			print('read',r,code,msg)
			if r then
				if stb.erase_en then
					print('erase',erase())
				end
				print('loadfile',loadfile(stb.path_firmware))
				print('go',go(stb.start_address))
			end
		end
	end
	print(close())
end