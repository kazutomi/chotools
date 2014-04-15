# coding: utf-8
$KCODE = 'UTF8' if RUBY_VERSION < '1.9.0'

require 'fileutils'

if RUBY_VERSION < "1.9.0"
  $KCODE = 'u'
end

module Cho
  TagLetters = %w(a b c d e f g h i j k l m n o p q r s t u v w x y z)
  NumToTag   = Hash.new
  TagToNum   = Hash.new

  # make tag mappings
  begin
    i = 0
    # one letter quick access
    TagLetters.each do |t|
      NumToTag[i] =  t
      TagToNum[t] = i
      i += 1
    end
    # two letters
    TagLetters.each do |t|
      TagLetters.each do |u|
        NumToTag[i] = t + u
        TagToNum[t + u] = i
        i += 1
      end
    end
  end

  def self.numtotag(num)
    if (tag = NumToTag[num])
      tag
    else
      nil
    end
  end

  def self.tagtonum(tag)
    if (num = TagToNum[tag])
      num
    else
      -1
    end
  end

  # Editor  = ENV['CHOEDITOR'] ? ENV['CHOEDITOR'] : 'open'	# XXX automatic editing moved to shell alias
  ChoHome = ENV['CHOHOME'] ? ENV['CHOHOME'] : ENV['HOME']	# base from which canonical dir name is calculated

  CacheFile  = "#{ChoHome}/.cho_cache"
  LockFile   = "#{ChoHome}/.cho_lock"
  IgnoreFile = "#{ChoHome}/.cho_ignore"

  Prefix              = '_cho_'
  CreatedDateFileName = "#{Prefix}created.txt"
  UsedDateFileName    = "#{Prefix}used.txt"
  TitleFileName       = "#{Prefix}title.txt"
  ChoFileNames        = [ CreatedDateFileName, UsedDateFileName, TitleFileName ]

  CreateExclusively = File::Constants::WRONLY | File::Constants::CREAT | File::Constants::EXCL

  # replacement of File.link, for environment where it does not work
  # raises Errno::EEXIST when lock cannot be obtained
  def self.lockandcopy(origfile, newlink)
    open(newlink, CreateExclusively, 0666) do |new|
      # lock obtained
      open(origfile, "r") do |orig|
        orig.each do |l|
          new.puts l
        end
      end
    end
  end

  # difference between two directories (dir - base)
  # Note: both dirs must be absolute so that the diff can be calculated on the string basis
  def self.diffdir(dir, base)
    b = base.split('/')
    d =  dir.split('/')
    # workaround for the terminal behaviour of split
    #  "/".split('/') #=> []
    # "/a".split('/') #=> ["", "a"]
    b = [''] if b.size == 0
    d = [''] if d.size == 0
    while b.size > 0 && d.size > 0 && b[0] == d[0]
      b.shift
      d.shift
    end
    diff = nil
    if b.size == 0 && d.size == 0  # base itself
      diff = '.'
    elsif b.size == 0  # dir is below the base
      diff = d.join('/')
    elsif d.size == 0  # dir is above the base
      diff = Array.new(b.size, '..').join('/')
    else
      diff = Array.new(b.size, '..').join('/') + '/' + d.join('/')
    end
    diff
  end

  # calculate the canonical path of a directory
  # Note: dir must exist
  def self.canondir(dir)
    relpath  = nil

    homepath = nil
    dirpath  = nil
    Dir.chdir(dir) do
      dirpath = Dir.pwd
    end
    Dir.chdir(ChoHome) do
      homepath = Dir.pwd
    end
    self.diffdir(dirpath, homepath)
  end

  # add str to top of the cache file
  # if str exists in the file, it is moved
  def self.toplist(str)
    rstr = Regexp.quote(str)
    r    = Regexp.new('^' + rstr + '$')

    FileUtils.touch(CacheFile)  # to ensure it exists

    self.lockandcopy(CacheFile, LockFile)
    File.unlink(CacheFile)

    open(LockFile, "r") do |lf|
      open(CacheFile, "w") do |cf|
        cf.puts str
        lf.each do |l|
          l.chomp!
          cf.puts l unless r =~ l
        end
      end
    end
    File.unlink(LockFile)
  end

  # remove str from the cache file
  # returns true if found str, false otherwise
  # XXX if multiple entries are found, they are all removed
  def self.removefromlist(str)
    rstr = Regexp.quote(str)
    r    = Regexp.new('^' + rstr + '$')

    self.lockandcopy(CacheFile, LockFile)
    File.unlink(CacheFile)

    found = false
    open(LockFile, "r") do |lf|
      open(CacheFile, "w") do |cf|
        lf.each do |l|
          l.chomp!
          if r =~ l
            found = true
          else
            cf.puts l
          end
        end
      end
    end
    File.unlink(LockFile)
    found
  end

  # replaces ostr with nstr in the cache file
  # without changing the order
  # if ostr is not found, nstr is placed on top
  def self.renameinlist(ostr, nstr)
    rstr = Regexp.quote(ostr)
    r    = Regexp.new('^' + rstr + '$')

    self.lockandcopy(CacheFile, LockFile)
    File.unlink(CacheFile)

    outstr = ""
    found = false
    open(LockFile, "r") do |f|
      f.each do |l|
        l.chomp!
        if r =~ l
          outstr << nstr << "\n"
          found = true
        else
          outstr << l << "\n"
        end
      end
    end
    if not found
      outstr = nstr + "\n" + outstr
    end

    open(CacheFile, "w") do |f|
      f.write(outstr)
    end

    File.unlink(LockFile)
  end

  def self.ignorefilenames
    ignoreFileNames = []
    begin
      open(IgnoreFile, "r") do |f|
        f.each do |l|
          ignoreFileNames << l.chomp
        end
      end
    rescue
      # no ignore-file
    end
    ignoreFileNames
  end

  # returns user file names in the current directory; ignore files are ignored
  def self.userfiles
    ignoreFileNames = self.ignorefilenames
    Dir.glob("*", File::Constants::FNM_DOTMATCH) - [ ".", ".." ] - ChoFileNames - ignoreFileNames
  end

  def self.ischodir?(dir = ".")
    # XXX may not sufficient to check only this, but fast and practical
    File.exist?(dir + "/" + Cho::CreatedDateFileName)
  end

  # put necessary files in the current directory
  # if there exist some, they are overwritten
  def self.newinfofiles
    t = Time.now
    open(CreatedDateFileName, "w", 0666) do |f|
      f.puts t.to_i.to_s
      f.puts t.to_s
    end
    open(UsedDateFileName, "w", 0666) do |f|
      f.puts t.to_i.to_s
      f.puts t.to_s
    end
    open(TitleFileName, "w", 0666) do |f|
      STDERR.print "Label: "
      f.puts STDIN.gets
    end
  end

  def self.unlinkchofiles
    ChoFileNames.each do |f|
      File.unlink(f)
    end
  end

  def self.unlinkignorefiles
    self.ignorefilenames.each do |f|
      begin
        FileUtils.remove_entry(f)  # may be directories or special files...
      rescue
        # to ignore errors on trying to remove nonexistent files
      end
    end
  end

  # update the used-date file (overwriting)
  def self.updateusedate
    t = Time.now
    open(UsedDateFileName, File::WRONLY) do |f|
      f.puts t.to_i.to_s
      f.puts t.to_s
    end
  end
end

#EOF
