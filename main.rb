require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'sinatra/config_file'
require 'haml'
require 'data_mapper'
require 'date'
require 'time'
require 'digest/sha2'

config_file 'config.yml'

$base_url = settings.base_url
$corp = settings.corp_name
$trusted_url_base = settings.trusted_url_base
$pointable_types = {C5: 'C5 Site', C3: 'C3 Site', G: 'Gas', P: 'PVP', O: 'Other'}
$unpointable_types = {Ore: 'Ore Site'}
$event_short_names = $pointable_types.merge($unpointable_types)
$event_types = $event_short_names.values
$db_path = settings.db_path

use Rack::Session::Cookie, expire_after: 21_600, secret: settings.cookie_secret

DataMapper.setup(:default, "sqlite3://" + $db_path)

# Human player, owns many characters
class Player
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :admin, Boolean, default: false
  property :password_hash_sha512, String, length: 150
  has n, :characters
  has n, :submissions
  has n, :approvals

  def active_characters
    result = []
    characters.each { |x| result << x if x.active }
    result
  end

  def events_participated_in(events)
    participated_events = []
    events.each do |event|
      unless $pointable_types.values.include?(event.event_type)
        # puts 'Exclude unpointable type ' + event.event_type
        next
      end
      participated = false
      event.characters.each do |character|
        participated = true if character.player == self
      end
      participated_events << event if participated
    end
    participated_events
  end

  def nonevents_participated_in(events)
    participated_events = []
    events.each do |event|
      unless $unpointable_types.values.include?(event.event_type)
        # puts 'Exclude unpointable type ' + event.event_type
        next
      end
      participated = false
      event.characters.each do |character|
        participated = true if character.player == self
      end
      participated_events << event if participated
    end
    participated_events
  end

  def nonevents_participated_value(events)
    value = 0
    nonevents_participated_in(events).each { |x| value += x.isk_per_player }
    value
  end

  def event_count_from(events)
    events_participated_in(events).count
  end

  def points_from(events, minimum_value)
    dates = {}
    events_participated_in(events).each do |event|
      post_downtime_date = event.event_time.to_date
      post_downtime_date -= 1 if event.event_time.hour < 11
      dates[post_downtime_date] = [] unless dates[post_downtime_date]
      dates[post_downtime_date] += [event]
    end
    points = 0
    isk = 0
    dates.each do |_date, date_events|
      # puts "Looking at " + date.to_s + " for " + name
      date_events.each { |x| isk += x.isk_per_player }
      # puts "Found " + isk.to_s + " isk"
      
      if isk >= minimum_value
          points += 1 
          isk = 0
      end
    end
    points
  end

  def password?
    password_hash_sha512 ? true : false
  end
end

# Join class showing which characters took part in an event
class Attendance
  include DataMapper::Resource
  property :id, Serial
  belongs_to :character
  belongs_to :event
end

# In-game character
class Character
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :active, Boolean, default: true
  belongs_to :player
  has n, :attendances
  has n, :events, through: :attendances
end

# Join class between players and events they submitted to the tool
class Submission
  include DataMapper::Resource
  property :id, Serial
  property :time, DateTime

  belongs_to :player
  has 1, :event
end

# Join class to show who approved an event
class Approval
  include DataMapper::Resource
  property :id, Serial
  property :time, DateTime

  belongs_to :player
  belongs_to :event
end

# A single 'thing' that happened (C3 site, gassing, PvP looting...)
class Event
  include DataMapper::Resource
  property :id, Serial
  property :description, String
  property :event_time, DateTime
  property :corner_value, Float
  property :event_type, String

  has n, :attendances
  has n, :characters, through: :attendances

  has 1, :approval
  belongs_to :submission

  def getCharactersString
    result = ''
    characters.each{|x|
      result += ', ' unless result.empty?
      result += x.name}
    result
  end

  def players
    players_active_in([self])
  end

  def getFormatDateTime
    event_time.strftime('%Y-%m-%d %H:%M')
  end

  def allow_edit(player, is_admin)
    return is_admin
    # Disable the previous (following) code because it allows unauthenticated editing
    # - bad news if someone fakes IGB headers
    # return true if is_admin
    # # return false if approval
    # submission.player == player
  end

  def isk_per_player
    players = []
    attendances.each { |x| players << x.character.player }
    # puts "count " + description + " " + players.uniq.count.to_s
    corner_value / players.uniq.count
  end
end

# Global configuration settings
class Configuration
  include DataMapper::Resource
  property :id, Serial
  property :minimum_point_value, Float
end

DataMapper::Model.raise_on_save_failure = true
DataMapper.finalize

Event.auto_upgrade!
Player.auto_upgrade!
Attendance.auto_upgrade!
Character.auto_upgrade!
Submission.auto_upgrade!
Approval.auto_upgrade!
Configuration.auto_upgrade!

def events_of_type(events, type)
  events.select { |event| event.event_type == type }
end

def players_active_in(events)
  players = []
  events.each { |event| event.characters.each { |character| players << character.player unless players.include?(character.player) } }
  players.sort! { |left, right| left.name <=> right.name }
  players
end

def getPendingEvents
  Event.all(order: [:event_time], approval: nil)
end

def getEvents(month, year)
  monthStart = DateTime.new(year, month, 1)
  monthEnd = DateTime.new(month == 12 ? year + 1 : year, (month % 12) + 1)
  Event.all(:order => [:event_time], :event_time.gte => monthStart, :event_time.lt => monthEnd)
end

def nowString
  DateTime.now.to_s
end

def getFilteredEvents(month, year, filter)
  events = getEvents(month, year)
  filter ? events.map { |event| filter.call(event) }.compact : events
end

def getNextLink(monthNumber, year, prefix)
  nowDate = DateTime.now
  nextMonth = monthNumber + 1
  nextYear = year
  if nextMonth == 13
    nextMonth = 1
    nextYear += 1
  end
  url = $base_url + prefix + nextYear.to_s + '/' + nextMonth.to_s + '/'
  month = Date::MONTHNAMES[nextMonth] + ' ' + nextYear.to_s
  return Hash[url: url, month: month] if nowDate.month > monthNumber or nowDate.year > year
end

def getPreviousLink(monthNumber, year, prefix)
  previousMonth = monthNumber - 1
  previousYear = year
  if previousMonth == 0
    previousMonth = 12
    previousYear -= 1
  end
  url = $base_url + prefix + previousYear.to_s + '/' + previousMonth.to_s + '/'
  month = Date::MONTHNAMES[previousMonth] + ' ' + previousYear.to_s
  Hash[url: url, month: month]
end

def getMonthReport(monthNumber, year)
  @month = Date::MONTHNAMES[monthNumber]
  @events = getFilteredEvents(monthNumber, year, lambda do|event|
      return event if event.approval
    end)
  @players = players_active_in(@events)
  @isk_total = 0
  @events.each { |event| @isk_total += event.corner_value }
  @isk_total *= 0.8 # to allow for stuff selling below corner value
  @isk_total = @isk_total.floor
  @point_total = 0
  @max_points = 0
  @players.each do |player|
    player_points = player.points_from(@events, @config.minimum_point_value)
    @point_total += player_points
    @max_points = [@max_points, player_points].max
  end
  @isk_point_average = (@point_total > 0 ? @isk_total / @point_total : 0).floor
  @previous_link = getPreviousLink(monthNumber, year, '/month/')
  @next_link = getNextLink(monthNumber, year, '/month/')
  @allow_delete = checkIsAdmin
  haml :month
end

def getCurrentPlayer
  if session['player_id']
    player = Player.first(id: session['player_id'])
    if player
      return player
    end
  end

  character_name = env['HTTP_EVE_CHARNAME']
  if not character_name or character_name == ''
    if settings.fake_igb_character
      character_name = settings.fake_igb_character
    end
  end
  character = Character.first(name: character_name, active: true)
  if character
    return character.player
  end

  if settings.dev_mode
    return Player.first_or_create(name: 'Default', admin: true)
  end
  nil
end

def checkIsAdmin
  if settings.dev_mode
    if @logged_in_player
      return @logged_in_player.admin
    end
    return false
  end
  # Do not allow admin by players who haven't authenticated, even if they're admins
  if session['player_id']
    player = Player.first(id: session['player_id'])
    if player
      return player.admin
    end
  end
  false
end

def hashOf(password)
  Digest::SHA512.hexdigest(settings.sha_salt + password)
end

def setLoggedInSession(player)
  if player
    session['player_id'] = player.id.to_s
  else
    session['player_id'] = ''
  end
end

before do
  if Configuration.count == 0
    @config = Configuration.create(minimum_point_value: 80)
  else
    @config = Configuration.first
  end
  pass if request.path_info == '/login/'
  @logged_in_player = getCurrentPlayer
  @now = nowString
  @isAdmin = checkIsAdmin
  if session['player_id'] && session['player_id'] != ''
    @isAuthenticated = true
  end
  unless @logged_in_player
    redirect '/login/'
  end
end

get '/logout/' do
  setLoggedInSession(nil)
  redirect '/'
end

get '/login/' do
  haml :login, layout: false
end

post '/login/' do
  name = params[:name]
  password = params[:password]
  player = Player.first(name: name)
  fail = true # Default to fail in case I make a mistake and allow a code path that doesn't catch a failure
  password_hash = hashOf(password)
  if player
    if password_hash == player.password_hash_sha512
      fail = false
      setLoggedInSession(player)
    else
      fail = true
    end
  else
    if Player.count == 0
      # We'll create an admin with the first char that logs in
      fail = false
      player = Player.create(name: name, admin: true, password_hash_sha512: password_hash)
      setLoggedInSession(player)
    else
      fail = true
    end
  end
  if fail
    @message = 'Login failed'
    return haml :login, layout: false
  end
  redirect '/'
end

get '/my/:year/:month/' do
  monthNumber = params[:month].to_i
  @year = params[:year].to_i
  @month = Date::MONTHNAMES[monthNumber]
  @approved_events = []
  @all_events = getFilteredEvents(monthNumber, @year, lambda{|event|
    participated = false
    event.characters.each { |character| participated = true if character.player == @logged_in_player }
    if participated
      @approved_events << event
    end
    event if participated})
  @points = @logged_in_player.points_from(@approved_events, @config.minimum_point_value)
  @previous_link = getPreviousLink(monthNumber, @year, '/my/')
  @next_link = getNextLink(monthNumber, @year, '/my/')
  haml :my
end

get '/my/' do
  now = DateTime.now
  redirect '/my/' + now.year.to_s + '/' + now.month.to_s + '/'
end

get '/month/:year/:month/' do
  @month = params[:month].to_i
  @year = params[:year].to_i
  getMonthReport(@month, @year)
end

get '/add_event/' do
  @create_or_edit = 'Create'
  @submit_relative_url = '/add_event/'
  @charactersArray = allCharactersJSON
  haml :edit_event
end

def allCharactersJSON
  '[' + Character.all(active: true).map { |x| '"' + x.name + '"' }.join(', ') + ']'
end

def createOrEditEvent(params, create)
  description = params[:description]
  if params[:event_time] and not params[:event_time].empty?
    begin
      event_time = Time.parse(params[:event_time] + 'Z').utc
    rescue
      @reason = 'Invalid time format: ' + params[:event_time] + $ERROR_INFO.to_s
      return haml :error
    end
  else
    event_time = Time.new.utc
  end

  corner_value = params[:corner_value].to_f
  event_type = params[:event_type]
  characters_string = params[:characters]
  if description.empty? or not $event_types.include?(event_type) or characters_string.empty? or corner_value <= 0.0 then
    @reason = 'Fill out all the fields'
    return haml :error
  end
  characters = []
  invalid_characters = []
  characters_string.split("\n").each {|x|
    character = Character.first(name: x.strip, active: true)
    if character then characters << character else invalid_characters << x end}
  unless invalid_characters.empty? then
    @reason = "Character doesn't exist (" + invalid_characters.join(', ') + ')'
    return haml :error
  end
  @charactersArray = allCharactersJSON
  if create
    submission = Submission.create(player: @logged_in_player, time: Time.new.utc)
    @event = Event.create(description: description, event_time: event_time, corner_value: corner_value, event_type: event_type, characters: characters, submission: submission)
    Approval.create(player: @logged_in_player, event: @event)
    @message = 'Event created'
    @create_or_edit = 'Edit'
    @submit_relative_url = '/edit_event/' + @event.id.to_s + '/'
    haml :edit_event
  else
    @event = Event.first(id: params[:id])
    unless @event
      @reason = 'Event ' + params[:id].to_s + "doesn't exist"
      haml :error
    end
    @event.update(description: description, event_time: event_time, corner_value: corner_value, event_type: event_type, characters: characters)
    @message = 'Event modified'
    @create_or_edit = 'Edit'
    @submit_relative_url = '/edit_event/' + @event.id.to_s + '/'
    haml :edit_event
  end
end

post '/add_event/' do
  createOrEditEvent(params, true)
end

get '/delete_event/:id/' do
  event = Event.first(id: params[:id])
  unless checkIsAdmin
    @reason = 'No access'
    return haml :error
  end
  unless event
    @reason = 'Event ' + id + " doesn't exist"
    return haml :error
  end
  event.attendances.destroy
  event.destroy
  redirect '/admin/'
end

get '/edit_event/:id/' do
  @event = Event.first(id: params[:id])
  unless @event
    @reason = 'Event ' + id + " doesn't exist"
    return haml :error
  end
  if checkIsAdmin || event.allow_edit(@logged_in_player)
    @create_or_edit = 'Edit'
    @submit_relative_url = '/edit_event/' + @event.id.to_s + '/'
    @charactersArray = allCharactersJSON
    haml :edit_event
  else
    @reason = 'No access'
    return haml :error
  end
end

post '/edit_event/:id/' do
  event = Event.first(id: params[:id])
  if checkIsAdmin or event.allow_edit(@logged_in_player)
    return createOrEditEvent(params, false)
  else
    @reason = 'No access'
    return haml :error
  end
end

post '/add_player/' do
  @name = params[:name]
  existing = Player.first(name: @name)
  if existing or !checkIsAdmin
    @reason = 'You tried to add a player that already exists (name=' + @name + ')'
    haml :error
  else
    player = Player.create(name: @name)
    redirect '/edit_player/' + player.id.to_s + '/'
    haml :add_player_success
  end
end

post '/add_character/' do
  @name = params[:name]
  existing = Character.first(name: @name, active: true)
  @player = Player.first(id: params[:player_id])
  if existing or !checkIsAdmin
    @reason = 'You tried to add a character that already exists (name=' + @name + ')'
    haml :error
  elsif !@player
    @reason = "Can't find the player you're trying to add a character to (id=" + params[:player_id] + ')'
    haml :error
  else
    Character.create(name: @name, player: @player, active: true)
    @message = "Character '" + @name + "' added to " + @player.name
    haml :edit_player
  end
end

def renderAdminPage
  @events = getPendingEvents
  @players = Player.all(order: [:name],)
  haml :admin
end

post '/set_minimum_point_value/' do
  config = Configuration.first
  unless checkIsAdmin
    @reason = 'No access'
    return haml :error
  end
  config.update(minimum_point_value: params[:value].to_f)
  redirect '/admin/'
end

get '/admin/' do
  unless checkIsAdmin
    @reason = 'Not Admin'
    return haml :error
  end
  renderAdminPage
end

get '/delete_character/:id/' do
  id = params[:id]
  character = Character.first(id: id)
  if character and checkIsAdmin
    character.update(active: false)
    @message = 'Character ' + character.name + ' removed.'
    @player = character.player
    haml :edit_player
  else
    @reason = "Character doesn't exist"
    haml :error
  end
end

post '/admin_reset_password/' do
  unless checkIsAdmin
    @reason = 'Not an admin'
    haml :error
  end
  @player = Player.first(id: params[:player_id])
  if @player
    password_hash = hashOf(params[:password])
    @player.update(password_hash_sha512: password_hash)
    @message = 'Updated password'
    redirect '/admin/'
  end
  @reason = 'No such player'
  haml :error
end

post '/edit_player/:id/' do
  id = params[:id]
  @player = Player.first(id: id)
  if @player && checkIsAdmin
    admin = false
    if params[:admin]
      admin = true
    end
    @player.update(name: params[:name], admin: admin)
    @message = 'Player updated'
    haml :edit_player
  else
    @reason = "You tried to edit a player that doesn't exist (id=" + id + ')'
    haml :error
  end
end

get '/edit_player/:id/' do
  id = params[:id]
  @player = Player.first(id: id)
  if @player && checkIsAdmin
    haml :edit_player
  else
    @reason = "You tried to edit a player that doesn't exist (id=" + id + ')'
  end
end

get '/' do
  now = DateTime.now
  redirect '/month/' + now.year.to_s + '/' + now.month.to_s + '/'
end


__END__
