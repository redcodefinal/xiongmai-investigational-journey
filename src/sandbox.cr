require "./requires"
socket = XMSocketTCP.new
socket.connect_target("192.168.1.10", 34567)
socket.login("admin", Dahua.digest "")
xmm = Command::SystemInfo::Request.new
socket.send_message xmm
puts socket.receive_message.message
puts "Please disconnect"
sleep 20
socket.connect_target("192.168.1.10", 34567)
socket.login("admin", Dahua.digest "")
xmm = Command::SystemInfo::Request.new
socket.send_message xmm
puts socket.receive_message.message
socket.close


#Command::Fuzzer::Gui.run

# mf = Command::FuzzerNew.new
# mf.run
# mf.wait






# sock = XMSocketTCP.new("192.168.1.99", 34567)
# sock.read_timeout = 5
# sock.login("admin", Dahua.digest "password")
# xmm = Command::SystemInfo::Request.new
# sock.send_message xmm
# puts sock.receive_message.message



# ## UP TESTER!
# sock_is_up = false

# until sock_is_up
#   begin


#     # xmm = XMMessage.new(command: 0x0678_u16, message: JSON.build do |json|
#     #   json.object do
#     #     json.field "Name", "OPDefaultConfig"
#     #     json.field "SessionID", "0x00000000"
#     #   end
#     # end)


#     counter = 1021_u16
#     start = Time.now

#     begin
#       while counter < 0x1000
#         sock = XMSocketTCP.new("192.168.1.99", 34567)
#         sock.read_timeout = 5
#         sock.login("admin", Dahua.digest "password")
#         sock_is_up = true

#         xmm = Command::Operation::DefaultConfig::Request.new

#         xmm.command = 0x05aa_u16
#         sock.send_message xmm
#         msg = sock.receive_message.message
#         puts "#{xmm.command.to_s(16)} #{msg}"
#         counter += 1
#         sleep 0.1
#       end
#     rescue e : XMError::ReceiveTimeout
#       puts "Was up for #{counter} times, #{Time.now - start}"
#     end
#   rescue e
#     puts "(LOGIN) Error #{e}"
#     sleep 1
#   end
# end

