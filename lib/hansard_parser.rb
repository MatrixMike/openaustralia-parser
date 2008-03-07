require 'speeches'
require 'id'
require 'speech'

class HansardHeading
  def initialize
    @title = ""
    @subtitle = ""
  end
  
  def output(x, newtitle, newsubtitle, speech_id, url)
    # Only add headings if they have changed
    if newtitle != @title
      x.tag!("major-heading", newtitle, :id => speech_id, :url => url)
    end
    if newtitle != @title || newsubtitle != @subtitle
      x.tag!("minor-heading", newsubtitle, :id => speech_id, :url => url)
    end
    @title = newtitle
    @subtitle = newsubtitle
  end
end

class HansardParser
  
  def HansardParser.parse_date(date, xml_filename, people)
    conf = Configuration.new

    # Required to workaround long viewstates generated by .NET (whatever that means)
    # See http://code.whytheluckystiff.net/hpricot/ticket/13
    Hpricot.buffer_size = 262144

    agent = WWW::Mechanize.new
    agent.set_proxy(conf.proxy_host, conf.proxy_port)

    url = "http://parlinfoweb.aph.gov.au/piweb/browse.aspx?path=Chamber%20%3E%20House%20Hansard%20%3E%20#{date.year}%20%3E%20#{date.day}%20#{Date::MONTHNAMES[date.month]}%20#{date.year}"
    page = agent.get(url)

    parse_day_page(page, date, agent, people, xml_filename)
  end
  
  def HansardParser.parse_sub_day_speech_page(link_text, sub_page, x, heading, speech_id, people, date)
    # Link text for speech has format:
    # HEADING > NAME > HOUR:MINS:SECS
    split = link_text.split('>').map{|a| a.strip}
    puts "Warning: Expected split to have length 3" unless split.size == 3
    time = split[2]
    # Extract permanent URL of this subpage. Also, quoting because there is a bug
    # in XML Builder that for some reason is not quoting attributes properly
    url = quote(sub_page.links.text("[Permalink]").uri.to_s)

    newtitle = sub_page.search('div#contentstart div.hansardtitle').inner_html
    newsubtitle = sub_page.search('div#contentstart div.hansardsubtitle').inner_html

    heading.output(x, newtitle, newsubtitle, speech_id, url)

    speeches = Speeches.new

    # Untangle speeches from subspeeches
    speech_content = Hpricot::Elements.new
    content = sub_page.search('div#contentstart > div.speech0 > *')
    tag_classes = content.map{|e| e.attributes["class"]}
    subspeech0_index = tag_classes.index("subspeech0")
    paraitalic_index = tag_classes.index("paraitalic")

    if subspeech0_index.nil?
      subspeech_index = paraitalic_index
    elsif paraitalic_index.nil?
      subspeech_index = subspeech0_index
    else
      subspeech_index = min(subspeech0_index, paraitalic_index)
    end

    if subspeech_index
      speech_content = content[0..subspeech_index-1]
      subspeeches_content = content[subspeech_index..-1]
    else
      speech_content = content
    end
    # Extract speaker name from link
    speaker = extract_speaker_from_talkername_tag(speech_content, people, date)
    speeches.add_speech(speaker, time, url, speech_id, speech_content)

    if subspeeches_content
      process_subspeeches(subspeeches_content, people, date, speeches, time, url, speech_id, speaker)
    end
    speeches.write(x)   
  end
  
  def HansardParser.parse_sub_day_page(link_text, sub_page, x, heading, speech_id, people, date)
    # Only going to consider speeches for the time being
    if link_text =~ /Speech:/
      parse_sub_day_speech_page(link_text, sub_page, x, heading, speech_id, people, date)
    else
      puts "WARNING: Skipping: #{link_text}"
    end
  end

  def HansardParser.parse_day_page(page, date, agent, people, xml_filename)
    xml = File.open(xml_filename, 'w')
    x = Builder::XmlMarkup.new(:target => xml, :indent => 1)

    heading = HansardHeading.new

    speech_id = Id.new("uk.org.publicwhip/debate/#{date}.")

    x.instruct!
    x.publicwhip do
      # Structure of the page is such that we are only interested in some of the links
      page.links[30..-4].each do |link|
        parse_sub_day_page(link.to_s, agent.click(link), x, heading, speech_id, people, date)
      end
    end

    xml.close
  end

  private
  
  def HansardParser.process_subspeeches(subspeeches_content, people, date, speeches, time, url, speech_id, speaker)
    # Now extract the subspeeches
    subspeeches_content.each do |e|
      tag_class = e.attributes["class"]
      if tag_class == "subspeech0" || tag_class == "subspeech1"
        speaker = extract_speaker_from_talkername_tag(e, people, date) || extract_speaker_in_interjection(e, people, date)
      elsif tag_class == "paraitalic"
        speaker = nil
      end
      speeches.add_speech(speaker, time, url, speech_id, e)
    end
  end

  def HansardParser.quote(text)
    text.sub('&', '&amp;')
  end

  def HansardParser.extract_speaker_from_talkername_tag(content, people, date)
    tag = content.search('span.talkername a').first
    if tag
      lookup_speaker(tag.inner_html, people, date)
    end
  end

  def HansardParser.extract_speaker_in_interjection(content, people, date)
    if content.search("div.speechType").inner_html == "Interjection"
      text = strip_tags(content.search("div.speechType + *").first)
      m = text.match(/([a-z].*) interjecting/i)
      if m
        name = m[1]
        lookup_speaker(name, people, date)
      else
        m = text.match(/([a-z].*)—/i)
        if m
          name = m[1]
          lookup_speaker(name, people, date)
        end
      end
    else
      throw "Not an interjection"
    end
  end

  def HansardParser.lookup_speaker(speakername, people, date)
    if speakername.nil?
      speakername = "unknown"
    end

    # HACK alert (Oh you know what this whole thing is a big hack alert)
    if speakername =~ /^the speaker/i
      speakername = "Mr David Hawker"
    # The name might be "The Deputy Speaker (Mr Smith)". So, take account of this
    elsif speakername =~ /^the deputy speaker/i
      speakername = "Mr Ian Causley"
    elsif speakername.downcase == "the clerk"
      # TODO: Handle "The Clerk" correctly
      speakername = "unknown"
    end
    # Lookup id of member based on speakername
    if speakername.downcase == "unknown"
      nil
    else
      people.find_house_member_by_name(Name.title_first_last(speakername), date)
    end
  end

  def HansardParser.strip_tags(doc)
    str=doc.to_s
    str.gsub(/<\/?[^>]*>/, "")
  end

  def HansardParser.min(a, b)
    if a < b
      a
    else
      b
    end
  end
end
