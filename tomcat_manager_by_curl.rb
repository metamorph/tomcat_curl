#!/usr/bin/env ruby
# vim:ai:sw=2:ts=2
# Provides a ruby wrapper for accessing the Tomcat management REST API through Curl.
# The reason for using Curl instead of direct net/http access is to allow this library 
# to be used with Capistrano (or net/ssh).

# Interface to create Curl commands agains the Tomcat endpoint.
class Curl
  def initialize(host, port, user, password)
	@host, @port, @user, @password = host, port, user, password
  end

  def command(name, options = {})
	base = "curl -s -u #{@user}:#{@password} http://#{@host}:#{@port}/manager/#{name}"
	unless options.empty?
	  base << "?" + options.map{|k,v| "#{k}=#{v}"}.join('&')
	end
	return Command.new(name, base)
  end

  # Wraps the command-line for Curl, and the concrete Command class that can handle the output from the command.
  class Command
	attr_reader :name, :command_line
	def initialize(name, command_line)
	  @name, @command_line = name, command_line
	end

	def run_local
	  puts "Executing #{@command_line}"
	  return response(`#{@command_line}`)
	end
	
	def response(curl_output)
	  klass = case @name
			  when 'list'
				ListResponse
			  when 'roles'
				RolesResponse
			  when 'resources'
				ResourcesResponse
			  when 'serverinfo'
				ServerInfoResponse
			  else
				Response
			  end
	  klass.new(curl_output)
	end

	class Response
	  attr_reader :summary, :lines
	  def initialize(curl_output)
		@summary = curl_output
		@lines = curl_output.split("\n").map{|l| l.strip}
		prepare unless fail?
	  end

	  def message
		@lines.first
	  end
	  def fail?
		message =~ /^FAIL/ ? true : false
	  end

	  protected

	  def prepare
		# 'Abstract' method impl. by subclasses.
	  end
	end

	class TupleResponse < Response
	  attr_reader :tuples 

	  def find_by(key, value)
		@tuples.select do |tuple|
		  tuple[key] == value
		end
	  end

	  def prepare
		@tuples = []
		keys = partitions() # Get partitions.
		if keys	
		  @lines[1..-1].each do |line|
			tuple = line.split(":")
			hash = {}
			keys.each do |k|
			  hash[k] = tuple[keys.index(k)]
			end
			@tuples << hash
		  end
		end
	  end

	  def partitions
		nil # Override in subclasses.
	  end
	end

	class ListResponse < TupleResponse
	  def partitions
		[:path, :status, :sessions, :name]
	  end
	end

	class RolesResponse < TupleResponse
	  def partitions
		[:name, :description]
	  end
	end

	class ResourcesResponse < TupleResponse
	  def partitions
		[:name, :type]
	  end
	end

	class ServerInfoResponse < TupleResponse
	  def partitions
		[:property, :value]
	  end
	end
  end
  
end

if __FILE__ == $0
  require 'pp'
  command = ARGV.shift
  options = {}
  ARGV.map{|pair| pair.split("=", 2)}.each do |k,v|
	options[k.to_sym] = v
  end

  curl = Curl.new('localhost', 8080, 'admin', 'admin')
  curl_command = curl.command(command, options)
  response = curl_command.run_local
  pp response
  puts "Command Failed: #{response.fail?}"
  puts "Summary:"
  puts response.summary

end
