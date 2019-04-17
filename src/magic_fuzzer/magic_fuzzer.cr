require "json"

require "../xmmessage"
require "../dahua_hash"
require "../commands/*"

require "./magic_error"
require "./magic_socket"
require "./magic_report"


class MagicFuzzer(Command)
  CLEAR_SCREEN = "\e[H\e[2J"

  private def clear_screen
    puts CLEAR_SCREEN
  end

  @factory_fiber : Fiber = spawn {}

  # Handles output
  @tick_fiber  : Fiber = spawn {}

  POOL_MAX = 20
  # List of what sockets are processing what magic
  @socket_pool = {} of MagicSocket => UInt16
  # List of sockets and it's current state
  @socket_states = {} of MagicSocket => String
  # List of sockets and the time they started
  @socket_times = {} of MagicSocket => Time

  # How many replies recieved
  @successful_replies = 0

  # Unique results, hash of the message => message
  @results = {} of UInt64 => String
  # Matches what message hash was returned with what magics.
  @results_matches = {} of UInt64 => Array(UInt16)
  # What magics failed in some way.
  @bad_results = {} of UInt16 => String
  
  @factory_state = :off

  @start_time : Time = Time.now
  MAX_TIMEOUT = 10
  
  CAMERA_WAIT_TIME = Time::Span.new(0, 0, 110)
  

  TEST = 0x12343
  @last_factory_check_in : Time = Time.now

  TCP_PORT = 34567

  getter? is_running = false

  SESSION_REGEX = /,?\h?\"SessionID\"\h\:\h\"0x.{8}\"/

  @current_magic = 0

  def initialize(@magic : Enumerable = (0x0000..0x08FF), 
          @output : IO = STDOUT,
          @username = "admin", 
          @password = "",
          hash_password = true,
          @login = true,
          @target_ip = "192.168.11.109")

    @password = Dahua.digest(@password) if hash_password

    #TODO: Make this work even if we cant connect to camera yet.
    make_pool
  end

  private def make_pool
    @socket_pool = {} of MagicSocket => UInt16
    @socket_states = {} of MagicSocket => String
    @socket_times = {} of MagicSocket => Time

    POOL_MAX.times do |i|
      success = false

      until success
        begin
          socket = MagicSocket.new(@target_ip, TCP_PORT)
          @socket_pool[socket] = 0
          @socket_states[socket] = "free"
          @socket_times[socket] = Time.now
          success = true
        rescue e
          if MagicError::SOCKET_ERRORS.includes? e.class
            clear_screen
            puts "Waiting for camera to come online"
          else
            raise e
          end
        end
      end
    end
  end

  private def replace_socket(old_sock, new_sock)
    @socket_pool.delete old_sock
    @socket_states.delete old_sock

    @socket_pool[new_sock] = 0
    @socket_times[new_sock] = @socket_times[old_sock]

    @socket_times.delete old_sock
    new_sock
  end

  private def find_free_socket
    sockets = (@socket_states.find { |socket, state| state == "free"})
    if sockets
      sockets[0]
    else
      nil
    end
  end

  def run
    unless is_running?
      @is_running = true
      @start_time = Time.now
      spawn_factory
      spawn_tick
    end
  end

  def close
    @socket_pool.each {|s, _| s.close}
    @is_running = false
  end

  private def factory_check_in
    @last_factory_check_in = Time.now
  end

  private def spawn_factory
    @factory_fiber = spawn do
      @factory_state = :on
      # Go through each magic sequence
      @magic.each do |magic|
        @factory_state = :incrementing

        @current_magic = magic
        # Attempt to find a free socket
        socket = nil
        until socket
          factory_check_in
          @factory_state = :finding
          socket = find_free_socket
          Fiber.yield
        end
        # If we did find a socket
        if socket
          @factory_state = :creating

          # Bind socket to magic
          @socket_pool[socket] = magic.to_u16
          spawn do
            found_socket = socket.as(MagicSocket)
            @socket_states[found_socket] = "started"
            @socket_times[found_socket] = Time.now

            # Make counter variables
            success = false

            # Until:
            #   There is success or,
            #   Max number of retries reached or,
            #   Max timeout reached
            until success || (Time.now- @socket_times[found_socket] ).to_i > MAX_TIMEOUT || !is_running?
              begin
                # Only login if we need to
                if @login
                  @socket_states[found_socket] = "logging_in"
                  # login, raises an error if login failed
                  found_socket.login(@username, @password)

                  @socket_states[found_socket] = "logged_in"
                end

                # make the message from the command class, with the custom magic
                c = Command.new(magic: magic.to_u16)
                
                # send
                found_socket.send_message c

                @socket_states[found_socket] = "sent_message"

                # yield to let other fibers have time
                Fiber.yield

                @socket_states[found_socket] = "recieving_message"

                # recieve reply
                m = found_socket.recieve_message
                @socket_states[found_socket] = "recieved_message"


                # at this point we got a reply, or we raised an error
                # checks to see if the reply is unique or not
                unless @results.keys.any? {|r| r == m.message.hash}
                  # Add it to the results
                  @results[m.message.hash] = m.message
                  # Add a new array for magic sequence results
                  @results_matches[m.message.hash] = [] of UInt16
                end
                # Add out results match
                @results_matches[m.message.hash] << magic.to_u16
                # Mark socket as unused
                @successful_replies += 1
                success = true
              rescue e
                # output the error to the socket's state
                @socket_states[found_socket] = "spawn socket: " + e.inspect
                # Check to see if it's an error we expect
                if MagicError::ALL_ERRORS.any? {|err| err == e.class}
                  # Restart the socket, close, reopen, and replace it
                  begin
                    # Replace the socket both in the pool, and in this fiber
                    found_socket = replace_socket(found_socket, MagicSocket.new(@target_ip, TCP_PORT))
                    @socket_pool[found_socket] = magic.to_u16
                  rescue e
                    if MagicError::SOCKET_ERRORS.includes? e.class
                      # The camera has crashed, so we need to wait until it comes back up
                      # Move the socket time forward CAMERA_WAIT_TIME seconds, to prevent time out due to crash
                      
                      # This ensures that the order of sockets is randomized to ensure that if a command is causing a disconnect, that some new 
                      # sockets will still be able to get through and resolve
                      random_wait_time = CAMERA_WAIT_TIME + Time::Span.new(0, 0, rand(10)+5)
                      @socket_times[found_socket] += random_wait_time
                      print "\a"
                      @socket_states[found_socket] = "SOCKET ERROR: SLEEPING #{random_wait_time} SECONDS"

                      sleep random_wait_time
                    end
                    @socket_states[found_socket] = "replace_socket: " + e.inspect
                  end
                else
                  # Mark bad socket, need to figure out how to handle this gracefully
                  @socket_states[found_socket] = "BAD ERROR!! " + e.inspect
                  raise e
                end
                sleep 1
              end
              # Attempt Fiber.yield once a loop
              Fiber.yield
            end
            #Add it to the bad results
            @bad_results[magic.to_u16] = e.inspect unless success
            @socket_states[found_socket] = "free"
          end
        end
        Fiber.yield
      end
      @factory_state = :done
    end
  end

  private def spawn_tick
    @tick_fiber = spawn do
      while is_running?
        tick
      end
    end
  end

  private def tick
    clear_screen
    puts "Fuzzing #{Command}"
    puts "Time: #{Time.now - @start_time}"
    puts "Current: #{@current_magic-@magic.begin}/#{@magic.size} : #{@current_magic.to_s(16)}"
    puts "Total Completion: #{(((@current_magic-@magic.begin).to_f / @magic.size.to_f)*100).round(3)}%"
    puts "Waiting for magics: "
    @socket_pool.values.sort{|a, b| a <=> b}.each do |magic|
      found_socket = @socket_pool.find{|k,v| v == magic}
      if found_socket
        socket = found_socket[0]
        if @socket_states[found_socket] != "free"
          puts "0x#{magic.to_s(16).rjust(4, '0')} : #{@socket_states[socket].rjust(80, ' ')} : #{found_socket.hash.to_s.rjust(20, ' ')} : #{(Time.now-@socket_times[socket]).to_s.rjust(20, ' ')}"
        end
      end
    end
    puts
    puts "Status"
    puts "Factory: #{@factory_state}"
    puts "Last Check In: #{@last_factory_check_in}"

    puts "Total Successes: #{@successful_replies}"
    puts "Total Unique Replies: #{@results.keys.size}"
    puts "Total Bad Results: #{@bad_results.keys.size}"
    puts 
    sleep 0.2
  end

  def wait_until_done
    until @socket_states.all? {|socket, state| state == "free"} && @factory_state == :done
      sleep 1
    end
  end

  def report
    mr = MagicReport.new @output
    mr.make(@start_time, @results, @results_matches, @bad_results)
  end
end


