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
	has n, :submissions
	has n, :approvals

	def getCharacters()
		activeCharacters = []
		characters.each{|x| activeCharacters << x if x.active}
		return activeCharacters
	end

	def getEventsParticipatedIn(events)
		participatedEvents = []
		events.each{|event| 
			participated = false
			event.characters.each{|character| participated = true if character.player == self}
			participatedEvents << event if participated}
		return participatedEvents
	end

	def getEventsFrom(events)
		return getEventsParticipatedIn(events).count
	end

	def getPointsFrom(events)
		dates = []
		getEventsParticipatedIn(events).each{|event| dates << event.event_time.to_date}
		return dates.uniq.count
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

class Submission
	include DataMapper::Resource
	property :id, Serial
	property :time, DateTime

	belongs_to :player
	has 1, :event
end

class Approval
	include DataMapper::Resource
	property :id, Serial
	property :time, DateTime

	belongs_to :player
	belongs_to :event
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

	has 1, :approval
	belongs_to :submission

	def getCharactersString()
		result = ""
		characters.each{|x|
			result += ", " if not result.empty?
			result += x.name}
		return result
	end
end

DataMapper::Model.raise_on_save_failure = true
DataMapper.finalize

Event.auto_upgrade!
Player.auto_upgrade!
Attendance.auto_upgrade!
Character.auto_upgrade!
Submission.auto_upgrade!
Approval.auto_upgrade!

def getPlayersActiveIn(events)
	players = []
	events.each{|event| event.characters.each{|character| players << character.player if not players.include?(character.player)}}
	return players
end

def getPendingEvents()
	Event.all(:order => [:event_time], :approval => nil)
end

def getEvents(month, year)
	monthStart = DateTime.new(year, month, 1)
	monthEnd = DateTime.new(month == 12 ? year + 1 : year, month + 1 % 12)
	Event.all(:order => [:event_time], :event_time.gte => monthStart, :event_time.lt => monthEnd)
end

def nowString()
	DateTime.now.to_s
end

def getMonthReport(monthNumber, year)
	@month = Date::MONTHNAMES[monthNumber]
	unfilteredEvents = getEvents(monthNumber, year)
	@pendingEventCount = 0
	@events = []
	unfilteredEvents.each{|event|
		if event.approval
			@events << event
		else
			@pendingEventCount += 1
		end}
	@players = getPlayersActiveIn(@events)
	@corp = "Hidden Agenda"
	@now = nowString()
	@isk_total = 0
	@events.each{|event| @isk_total += event.corner_value}
	@point_total = 0
	@players.each{|player| @point_total += player.getPointsFrom(@events)}
	@isk_point_average = @point_total > 0 ? @isk_total / @point_total : 0
	@allow_edit = checkIsAdmin()
	haml :month
end

def getCurrentPlayer()
	character_name = env['HTTP_EVE_CHARNAME']
	character = Character.first(:name => character_name, :active => true)
	if character
		return character.player
	end
	Player.first_or_create(:name => "Default")
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
	@create_or_edit = "Create"
	@submit_relative_url = "/add_event/"
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
	haml :edit_event
end

def createOrEditEvent(params, create)
	description = params[:description]
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
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
	characters_string.split("\n").each {|x|
		character = Character.first(:name => x.strip, :active => true)
		if character then characters << character else invalid_characters << x end}
	if not invalid_characters.empty? then
		@reason = "Character doesn't exist (" + invalid_characters.join(", ") + ")"
		return haml :error
	end
	if create
		submission = Submission.create(:player => @logged_in_player, :time => Time.new.utc)
		@event = Event.create(:description => description, :event_time => event_time, :corner_value => corner_value, :event_type => event_type, :characters => characters, :submission => submission)
		@message = "Event created"
		@create_or_edit = "Edit"
		@submit_relative_url = "/edit_event/" + @event.id.to_s + "/"
		haml :edit_event
	else
		@event = Event.first(:id => params[:id])
		if not @event
			@reason = "Event " + params[:id].to_s + "doesn't exist"
			haml :error
		end
		@event.update(:description => description, :event_time => event_time, :corner_value => corner_value, :event_type => event_type, :characters => characters)
		@message = "Event modified"
		@create_or_edit = "Edit"
		@submit_relative_url = "/edit_event/" + @event.id.to_s + "/"
		haml :edit_event
	end
end

post '/add_event/' do
	createOrEditEvent(params, true)
end



get '/edit_event/:id/' do
	@event = Event.first(:id => params[:id])
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
	if not @event
		@reason = "Event " + id + " doesn't exist"
		return haml :error
	end
	if checkIsAdmin() or (@event.submission.player == @logged_in_player and not @event.approval)
		@create_or_edit = "Edit"
		@submit_relative_url = "/edit_event/" + @event.id.to_s + "/"
		haml :edit_event
	else
		@reason = "No access"
		return haml :error
	end
end

post '/edit_event/:id/' do
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
	if checkIsAdmin() or (@event.submission.player == @logged_in_player and not @event.approval)
		return createOrEditEvent(params, false)
	else
		@reason = "No access"
		return haml :error
	end
end

post '/add_player/' do
	@logged_in_player = getCurrentPlayer()
	@name = params[:name]
	@now = nowString()
	existing = Player.first(:name => @name)
	if existing or not checkIsAdmin()
		@reason = "You tried to add a player that already exists (name=" + @name + ")"
		haml :error
	else
		player = Player.create(:name => @name)
		puts player.name
		puts player.saved?
		haml :add_player_success
	end
end

post '/add_character/' do
	@logged_in_player = getCurrentPlayer()
	@name = params[:name]
	@now = nowString()
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

def renderAdminPage()
	@events = getPendingEvents()
	@players = Player.all(:order => [:name], )
	haml :admin
end

get '/approve_event/:id/' do
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
	if not checkIsAdmin()
		@reason = "Not Admin"
		return haml :error
	end
	event = Event.first(:id => params[:id])
	Approval.create(:player => @logged_in_player, :event => event)
	renderAdminPage()
end


get '/admin/' do
	@logged_in_player = getCurrentPlayer()
	@allow_approval = true
	@allow_edit = true
	@now = nowString()
	if not checkIsAdmin()
		@reason = "Not Admin"
		return haml :error
	end
	renderAdminPage()
end

get '/delete_character/:id/' do
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
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
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
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
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
	id = params[:id]
	@player = Player.first(:id => id)
	if @player and checkIsAdmin()
		haml :edit_player
	else
		@reason = "You tried to edit a player that doesn't exist (id=" + id + ")"
	end
end

get '/' do
	@logged_in_player = getCurrentPlayer()
	@now = nowString()
	now = DateTime.now
	@year = now.year
	@month = now.month
	getMonthReport(@month, @year)
end


__END__

