require 'rubygems'
require 'rest_client'
require 'xmlsimple'
require 'json'
require 'zip'
require 'csv'
require 'io/console'



login = ARGV[0];
password = ARGV[1];

puts 'start'
#puts "Enter your user-name"
#user_name=STDIN.gets.chomp()
#puts "Enter your password"
#password=STDIN.noecho(&:gets)


values = '{
  "postUserLogin": {
    "login": "' + ARGV[0] + '",
    "password": "' + ARGV[1] + '",
    "remember": 1
  }
}'

headers = {
  :accept => 'application/json',
  :content_type => 'application/json'
}

response = RestClient.post 'https://secure.gooddata.com/gdc/account/login', values, headers
user =  JSON.parse(response)
uId = user["userLogin"]["profile"].split("/")[4]
puts "Your user id is " + uId
puts "---------------------------------------------------------------"


#get SST token
GDCAuthSST = response.cookies["GDCAuthSST"]

headers = {
  :accept => 'application/json',
  :content_type => 'application/json',
  :cookie => '$Version=0; GDCAuthSST=' + GDCAuthSST + '; $Path=/gdc/account'
}

response = RestClient.get 'https://secure.gooddata.com/gdc/account/token', headers

#get TT token
GDCAuthTT = response.cookies["GDCAuthTT"]


headers = {
  :accept => 'application/json',
  :cookie => '$Version=0; GDCAuthTT=' + GDCAuthTT + '; $Path=/gdc ; secure; HttpOnly'
}


#List all projects 

projectIds = RestClient.get "https://secure.gooddata.com/gdc/account/profile/" + uId + "/projects" , headers
pParsed = JSON.parse(projectIds)
items = pParsed["projects"]
#project_Id = Array.new
#project_Name = Array.new

project_Id = Hash.new
project_Id_number=Array.new
project_Id_number_h=Hash.new



i=1
#iterate thru each project to get project_id & project_name
items.each { |x|
  link = x["project"]["links"]["self"].split("/")[3]
  name = x["project"]["meta"]["title"]
  project_Id.store(name,link)
  project_Id_number_h.store(i,name)
  project_Id_number << i  
  i=i+1	
  }
puts "Listing all the projects,Please select the appropriate proejct" 
#puts project_Id.keys
limit=project_Id_number.length
for i in 1..limit 
puts "#{i}." + project_Id_number_h[i] 
 end
puts "--------------------------------------------------------------------------------"
pro_name=STDIN.gets.chomp().to_i
#puts project_Id[pro_name]
id=project_Id[project_Id_number_h[pro_name]]


#List Process-ids for a particular project 
processIds = RestClient.get "https://secure.gooddata.com/gdc/projects/" + project_Id[project_Id_number_h[pro_name]] + "/dataload/processes", headers
parsed = JSON.parse(processIds)

items = parsed["processes"]["items"]
process_Id=Hash.new
process_Id_number=Array.new
process_Id_number_h=Hash.new

i=1
#iterate thru all process Ids
items.each { |x|
  link = x["process"]["links"]["self"].split("/")[6]
  temp = x["process"]["name"]
 
   process_Id.store(temp,link)
   process_Id_number_h.store(i,temp)
   process_Id_number << i  
   i=i+1	
  }
limit=process_Id_number.length
puts "Listing all the processes for project:" 
for i in 1..limit 
puts "#{i}." + process_Id_number_h[i] 
 end

#puts "Listing all the processes for project:" +  pro_name 
#puts process_Id.keys
puts "--------------------------------------------------------------------------------"
proc_name=STDIN.gets.chomp().to_i
#puts process_Id[proc_name]
puts "--------------------------------------------------------------------------------"


#Downloading archives by process-ids
zipArchive=RestClient.get "https://secure.gooddata.com/gdc/projects/" + id + "/dataload/processes/" + process_Id[process_Id_number_h[proc_name]] + "/source" , headers
File.delete("test_ruby_4.zip") if File.exist?("test_ruby_4.zip")
File.open('test_ruby_4.zip', 'w') {|f| f.write(zipArchive) }


#Unizipping zip file

destination = 'ext'
FileUtils.rm_rf('ext')

Zip::File.open("test_ruby_4.zip") do |zipfile|
  zipfile.each do |entry|
    zipfile.each { |f|
     if /.*\.grf/ =~ f.name
      f_path=File.join(destination, /(.*)(\/)(.+\.grf)/.match(f.name)[3])
      FileUtils.mkdir_p(File.dirname(f_path))
      zipfile.extract(f, f_path) unless File.exist?(f_path)
      end
    }
  end
end


# Creating CSV Files

puts 'start'
puts "Which graph do you want to Document"
puts "--------------------------------------------------------------------------------"
#puts Dir.entries("ext").select {|f| !File.directory? f}
a=Dir.entries("ext").select {|f| !File.directory? f}

limit=a.length
for i in 1..limit 
puts "#{i}." + a[i-1] 
 end 


puts "--------------------------------------------------------------------------------"
name=STDIN.gets.chomp().to_i

CNAME_RE = /(.*):(.*)/
NA_STRING = "--N/A--"
usedMeta = Array.new

fileGraph = 'ext/' +a[name]

graph = XmlSimple.xml_in(fileGraph)
phases = graph["Phase"]
metadata = graph["Global"][0]["Metadata"]

CSV.open(fileGraph + '.csv', "wb") do |csv|
  csv << ["Phase No.", "Component Name", "Component ID", "From Component", "To Component", "Transform", "Output Metadata ID"]

  phases.each { |x|

    compArr = Array.new

    if !x["Edge"].nil?

      x["Edge"].each { |edge|

      # link with node
        comp = CNAME_RE.match(edge["fromNode"])[1]
        y = x["Node"][x["Node"].index{|zz| zz["id"] == comp}]
        # link with metadata
        meta = metadata[metadata.index{|mm| mm["id"] == edge["metadata"]}]
        usedMeta << meta["id"]
        compArr << y["id"]
        #puts x["number"]
        #puts y["id"]

        case y["type"]
        when "REFORMAT"
          #puts 'reformat'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["attr"][0]["content"], edge["metadata"]]

        when "DATA_READER"
          #puts 'data reader'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["fileURL"], edge["metadata"]]

        when "DATA_WRITER"
          #puts 'data writer'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["fileURL"], edge["metadata"]]

        when "DEDUP"
          #puts 'DEDUP'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["dedupKey"], edge["metadata"]]

        when "FILE_LIST"
          #puts 'FILE_LIST'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["baseURL"], edge["metadata"]]

        when "PARTITION"
          #puts 'PARTITION'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["attr"][0]["content"], edge["metadata"]]

        when "SIMPLE_GATHER"
          #puts 'SIMPLE_GATHER'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], NA_STRING, edge["metadata"]]

        when "FILE_COPY_MOVE"
          #puts 'FILE_COPY_MOVE'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["targetPath"], edge["metadata"]]

        when "TRASH"
          #puts 'TRASH'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["targetPath"], edge["metadata"]]

        when "DB_INPUT_TABLE"
          #puts 'DB_INPUT_TABLE'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["attr"][0]["content"], edge["metadata"]]

        when "DB_EXECUTE"
          #puts 'DB_INPUT_TABLE'
          csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], y["attr"][0]["content"], edge["metadata"]]

        else
        #puts 'default'
        csv << [x["number"], y["guiName"], y["id"], edge["fromNode"], edge["toNode"], NA_STRING, edge["metadata"]]
        end
      }
    end

    if !x["Node"].nil?

      x["Node"].each { |y|
        #puts y["id"]
        if !compArr.include?(y["id"])
          csv << [x["number"], y["guiName"], y["id"], NA_STRING, NA_STRING, NA_STRING, NA_STRING]
        end
      }
    end
    compArr.clear
  }

  x = 0

end

CSV.open(fileGraph + '_meta.csv', "wb") do |csv|
  csv << ["ID", "Name", "Field Name", "Field Type", "Is Used"]

  metadata.each { |x|
    isUsed = "No"
    if usedMeta.include?(x["id"])
      isUsed = "Yes"
    end

    if !x["Record"].nil?
      x["Record"][0]["Field"].each { |y|
        csv << [x["id"], x["Record"][0]["name"], y["name"], y["type"], isUsed]
      }
    else
      csv << [x["id"], x["fileURL"], NA_STRING, NA_STRING]
    end
  }
end

puts "Two CSV files are created for The graph. Please check in the ext folder"
puts 'end'
