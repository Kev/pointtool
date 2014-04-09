require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'haml'
require 'data_mapper'
require 'date'

$base_url = ""

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/points.db")

class Player
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	has n, :characters
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
	belongs_to :player
	has n, :attendances
	has n, :events, :through => :attendances
end

class Event
	include DataMapper::Resource
	property :id, Serial
	property :description, String
	property :when, DateTime
	has n, :attendances
	has n, :characters, :through => :attendances
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

post '/add_player/' do
	@name = params[:name]
	existing = Player.first(:name => @name)
	if existing
		haml :add_player_fail
	else
		Player.create(:name => @name)
		haml :add_player_success
	end
end

get '/admin/' do
	@players = Player.all(:order => [:name], )
	haml :admin
end

post '/edit_player/:id/' do
	id = params[:id]
	@player = Player.first(:id => id)
	if @player and checkIsAdmin()
		@player.update(:name => params[:name])
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
		haml :error
	end
end

get '/' do
	now = DateTime.now
	@year = now.year
	@month = now.month
	getMonthReport(@month, @year)
end


__END__

