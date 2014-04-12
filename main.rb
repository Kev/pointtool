require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'haml'
require 'data_mapper'
require 'date'
require 'time'

$base_url = ""
$event_types = ["C5 Site", "C3 Site", "Gas", "PVP", "Other"]

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/points.db")

class Player
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	has n, :characters

	def getCharacters()
		activeCharacters = []
		characters.each{|x| activeCharacters << x if x.active}
		return activeCharacters
	end
end

class Attendance
	include DataMapper::Resource
	property :id, Serial
	belongs_to :character
	belongs_to :event
end

class Character
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	property :active, Boolean, :default => true
	belongs_to :player
	has n, :attendances
	has n, :events, :through => :attendances
end

class Event
	include DataMapper::Resource
	property :id, Serial
	property :description, String
	property :event_time, DateTime
	property :corner_value, Float
	property :event_type, String
	has n, :attendances
	has n, :characters, :through => :attendances

	def getCharactersString()
		result = ""
		characters.each{|x|
			result += ", " if not result.empty?
			result += x.name}
		return result
	end
end

DataMapper.finalize

Event.auto_upgrade!
Player.auto_upgrade!
Attendance.auto_upgrade!
Character.auto_upgrade!

def getEvents(month, year)
	Event.all(:order => [:when], )
end

def getMonthReport(monthNumber, year)
	@month = Date::MONTHNAMES[monthNumber]
	@events = getEvents(@month, year)
	@corp = "Hidden Agenda"
	@now = DateTime.now.to_s
	haml :month
end

def checkIsAdmin()
	true
end

get '/month/:year/:month/' do 
	@month = params[:month]
	@year = params[:year]
	getMonthReport(@month, @year)
end

get '/add_event/' do
	Player.create(:name => @name)
	@create_or_edit = "Create"
	@submit_relative_url = "/add_event/"
	haml :edit_event
end

post '/add_event/' do
	description = params[:description]
	if params[:event_time] and not params[:event_time].empty?
		begin
			event_time = Time.parse(params[:event_time]).utc
		rescue
			@reason = "Invalid time format: " + params[:event_time] + $!.to_s
			return haml :error
		end
	else
		event_time = Time.new.utc
	end
	
	corner_value = params[:corner_value].to_f
	event_type = params[:event_type]
	characters_string = params[:characters]
	if description.empty? or not $event_types.include?(event_type) or characters_string.empty? or corner_value <= 0.0 then
		@reason = "Fill out all the fields"
		return haml :error
	end
	characters = []
	invalid_characters = []
	characters_string.split(",").each {|x|
		character = Character.first(:name => x, :active => true)
		if character then characters << character else invalid_characters << x end}
	if not invalid_characters.empty? then
		@reason = "Character doesn't exist (" + invalid_characters.join(", ") + ")"
		return haml :error
	end
	@event = Event.create(:description => description, :event_time => event_time, :corner_value => corner_value, :event_type => event_type, :characters => characters)
	@message = "Event created"
	@create_or_edit = "Edit"
	@submit_relative_url = "/edit_event/"
	haml :edit_event
end

post '/add_player/' do
	@name = params[:name]
	existing = Player.first(:name => @name)
	if existing or not checkIsAdmin()
		@reason = "You tried to add a player that already exists (name=" + @name + ")"
		haml :error
	else
		Player.create(:name => @name)
		haml :add_player_success
	end
end

post '/add_character/' do
	@name = params[:name]
	existing = Character.first(:name => @name, :active => true)
	@player = Player.first(:id => params[:player_id])
	if existing or not checkIsAdmin()
		@reason = "You tried to add a character that already exists (name=" + @name + ")"
		haml :error
	elsif not @player
		@reason = "Can't find the player you're trying to add a character to (id=" + params[:player_id] + ")"
		haml :error
	else
		Character.create(:name => @name, :player => @player, :active => true)
		@message = "Character '" + @name + "' added to " + @player.name
		haml :edit_player
	end
end

get '/admin/' do
	@players = Player.all(:order => [:name], )
	haml :admin
end

get '/delete_character/:id/' do
	id = params[:id]
	character = Character.first(:id => id)
	if character and checkIsAdmin()
		character.update(:active => false)
		@message = "Character " + character.name + " removed."
		@player = character.player
		haml :edit_player
	else
		@reason = "Character doesn't exist"
		haml :error
	end
end

post '/edit_player/:id/' do
	id = params[:id]
	@player = Player.first(:id => id)
	if @player and checkIsAdmin()
		@player.update(:name => params[:name])
		@message = "Name updated"
		haml :edit_player
	else
		@reason = "You tried to edit a player that doesn't exist (id=" + id + ")"
		haml :error
	end
end

get '/edit_player/:id/' do
	id = params[:id]
	@player = Player.first(:id => id)
	if @player and checkIsAdmin()
		haml :edit_player
	else
		@reason = "You tried to edit a player that doesn't exist (id=" + id + ")"
	end
end

get '/' do
	now = DateTime.now
	@year = now.year
	@month = now.month
	getMonthReport(@month, @year)
end


__END__

