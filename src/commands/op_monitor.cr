class Command::OPMonitor < XMMessage
  COMBIN_MODES = ["CONNECT_ALL", "NONE"]
  ACTIONS = ["Claim"]
  ACTION1S = ["Start"]
  STREAM_TYPES = ["Main", "Extra1"]
  TRANS_MODES = ["TCP"]


  def initialize(magic = 0x0585_u16, session_id = 0_u32)
    super(magic: magic, session_id: session_id, message:  JSON.build do |json|
      json.object do
        json.field "Name", "OPMonitor"
        json.field "OPMonitor" do
          json.object do
            json.field "Action", "Claim"
            json.field "Parameter" do
              json.object do
                json.field "Channel", 0
                json.field "CombinMode", "NONE"
                json.field "StreamType", "Main"
                json.field "TransMode", "TCP"
              end
            end
          end
        end
        json.field "SessionID", "0x#{session_id.to_s(16).rjust(8, '0').capitalize}"
      end
    end)
  end
end

# magic1: 0x85 
# magic2: 0x05
#
#}
# 	"Name":	"OPMonitor",
# 	"OPMonitor":	{
# 		"Action":	"Claim",
# 		"Parameter":	{
# 			"Channel":	0,
# 			"CombinMode":	"CONNECT_ALL",
# 			"StreamType":	"Main",
# 			"TransMode":	"TCP"
# 		}
# 	},
# 	"SessionID":	"0x000001869f"
# }
# GOT RET 103

# magic1: 0x85 
# magic2: 0x05
#
#{
# 	"Name":	"OPMonitor",
# 	"OPMonitor":	{
# 		"Action":	"Claim",
# 		"Action1":	"Start",
# 		"Parameter":	{
# 			"Channel":	0,
# 			"CombinMode":	"NONE",
# 			"StreamType":	"Extra1",
# 			"TransMode":	"TCP"
# 		}
# 	},
# 	"SessionID":	"0x0000000007"
# }
# GOT RET 100

# magic1: 0x82
# magic2: 0x05
#
#{
# 	"Name":	"OPMonitor",
# 	"OPMonitor":	{
# 		"Action":	"Claim",
# 		"Action1":	"Start",
# 		"Parameter":	{
# 			"Channel":	0,
# 			"CombinMode":	"NONE",
# 			"StreamType":	"Main",
# 			"TransMode":	"TCP"
# 		}
# 	},
# 	"SessionID":	"0x0000000007"
# }
# GOT RET 103
