package.path = '/workspace/zdc/lua/?.lua;/workspace/zdc/lib/lua/?.lua;'..package.path
package.path = '/workspace/zdc/lua/zsvc/?.lua;/workspace/zdc/lua/zai/?.lua;/workspace/zdc/?.lua;'..package.path
package.cpath = '/workspace/zdc/lib/mac64/?.so;'..package.cpath

local rs232 = require("luars232")
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
assert(p:set_parity(rs232.RS232_PARITY_NONE) == rs232.RS232_ERR_NOERROR)
assert(p:set_stop_bits(rs232.RS232_STOP_1) == rs232.RS232_ERR_NOERROR)
assert(p:set_flow_control(rs232.RS232_FLOW_OFF)  == rs232.RS232_ERR_NOERROR)

out:write(string.format("OK, port open with values '%s'\n", tostring(p)))

print(p:read(1, 100))
print(p:write("test"))
print(p:read(6, 100))

assert(p:close() == rs232.RS232_ERR_NOERROR)

