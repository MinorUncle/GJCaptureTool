#!/usr/bin/ruby -w


require 'xcodeproj'

def dealFile(pGroup ,pTarget, fileKeys,fileValue)
    add_file_refs = Array.new();
    delete_file_refs = Array.new();
    i = 0
    for fileName in fileKeys
        file_ref = pGroup.find_file_by_path(fileName)
        puts "file_ref: #{file_ref}   fileName: #{fileName}"
        if file_ref != nil
            puts("name:#{fileKeys[i]} value:#{fileValue[i]}")

            if fileValue[i].to_i == 1
            add_file_refs.push(file_ref)
            puts("add_file_refs#{file_ref}")

            elsif fileValue[i].to_i == 0
            delete_file_refs.push(file_ref)
            puts("delete_file_refs#{file_ref}")

            end
        end
        i = i+1
    end
    puts "file_refs: #{add_file_refs}"
    puts "delete_file_refs: #{delete_file_refs}"

    addfile = pTarget.add_file_references(add_file_refs)
    for delFile in delete_file_refs
        pTarget.source_build_phase.remove_file_reference(delFile)
        puts "remove_file_reference: #{delFile}"

    end
    puts "addfile: #{addfile}"
end



def praseArgv(key,value)
    puts( "argv #{ARGV}")

    ARGV.each{|item|
        items = item.split(':')
        i = 0
        while i<key.length
            if key[i] == items[0]
                if items[1] == 1
                    value[i] = 1
                end
                break
            end
            i = i+1
        end
        if i == key.length
            key.push(items[0])
            value.push(items[1])
        end
    }

end


#project_path = '/Users/tongguan/Develop/ffmpegCode副本/ffmpegCode.xcodeproj'

fileKey = Array.new()
fileValue = Array.new()


groupName = ARGV[0]
targetName = ARGV[1]
project_path = ARGV[2]

ARGV.shift
ARGV.shift
ARGV.shift


praseArgv(fileKey,fileValue)
#
#i=0
#while i<fileKey.length
#    puts(fileKey[i])
#    puts(fileValue[i])
#    i = i+1
#end

project = Xcodeproj::Project.open(project_path)
puts "project_path:#{project_path} project:#{project}"

targets = project.targets
for target in targets
    if target.name == targetName
        break;
    end
end
puts "targetName:#{targetName}  targets:#{targets}  target:#{target}"
group = project.main_group.find_subpath(groupName, false)
puts "group:#{group} groupName:#{groupName}"
dealFile(group,target,fileKey,fileValue)
project.save

