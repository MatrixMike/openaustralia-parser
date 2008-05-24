require 'period'
require 'id'

class Person
  attr_reader :periods, :person_count, :name, :minister_positions
  
  def Person.reset_id_counter
    @@next_person_count = 10001
  end
  
  reset_id_counter
  
  def id
    "uk.org.publicwhip/person/#{@person_count}"
  end
  
  def initialize(name, override_person_count = nil)
    @periods = []
    @minister_positions = []
    if override_person_count
      @person_count = override_person_count
    else
      @person_count = @@next_person_count
      @@next_person_count = @@next_person_count + 1
    end
    @name = name
  end
  
  # Does this person have current senate/house of representatives positions on the given date
  def current_position_on_date?(date)
    @periods.detect {|p| p.current_on_date?(date)}
  end
  
  def house_periods
    @periods.find_all{|p| p.house == "representatives"}
  end
  
  # Returns the period which is the latest in time
  def latest_period
    @periods.sort {|a, b| a.to_date <=> b.to_date}.last
  end
  
  def add_period(params)
    @periods << Period.new(params.merge(:person => self))
  end
  
  # Adds a single continuous period when this person was in the house of representatives
  # Note that there might be several of these per person
  def add_house_period(params)
    add_period(params.merge(:house => "representatives"))
  end
  
  def add_minister_position(params)
    @minister_positions << MinisterPosition.new(params.merge(:person => self))
  end
  
  # Returns true if this person has a house_period with the given id
  def has_period_with_id?(id)
    !find_period_by_id(id).nil?
  end
  
  def find_period_by_id(id)
    @periods.find{|p| p.id == id}
  end
  
  def ==(p)
    id == p.id && periods == p.periods
  end
end
