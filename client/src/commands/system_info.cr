class Command::SystemInfo < Command
  def initialize(@session_id = 0)
    super(magic1: 0xfc_u8, magic2: 0x03_u8, json: JSON.build do |json|
      json.object do
        json.field "Name", "SystemInfo"
        json.field "SessionID", "0x#{@session_id.to_s(16).rjust(8, '0')}"
      end
    end)
  end
end