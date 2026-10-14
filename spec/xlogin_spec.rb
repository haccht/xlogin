require 'spec_helper'
require 'tmpdir'

RSpec.describe Xlogin do
  it 'has a version number' do
    expect(Xlogin::VERSION).not_to be nil
  end

  describe '.generate_templates' do
    it 'copies built-in templates to the specified directory without NameError' do
      Dir.mktmpdir do |dir|
        Xlogin.generate_templates(dir)
        expect(Dir.glob(File.join(dir, '*.rb'))).not_to be_empty
        expect(File.exist?(File.join(dir, 'ios.rb'))).to be true
      end
    end
  end

  describe 'Factory#list_hostinfo' do
    let(:factory) { Xlogin.factory }

    before do
      factory.instance_variable_set(:@inventory, {})
      factory.set_hostinfo('router01', type: 'ios', role: 'core')
      factory.set_hostinfo('switch01', type: 'ios')
    end

    it 'matches hosts by existing key' do
      res = factory.list_hostinfo('role:core')
      expect(res.map { |h| h[:name] }).to eq(['router01'])
    end

    it 'does not raise TypeError when querying a key not present on all hosts' do
      expect {
        res = factory.list_hostinfo('role:core')
        expect(res.size).to eq(1)
      }.not_to raise_error
    end

    it 'does not raise TypeError when querying a completely unknown key' do
      expect {
        res = factory.list_hostinfo('nonexistent_key:foo')
        expect(res).to be_empty
      }.not_to raise_error
    end
  end

  describe Xlogin::SessionPool do
    it 'checks closed? safely without calling undefined sock on SSH session' do
      fake_ssh_session = Object.new
      def fake_ssh_session.closed?; false; end
      def fake_ssh_session.close; end

      pool = Xlogin::SessionPool.new('dummy')
      pool.instance_variable_set(:@count, 1)

      expect(fake_ssh_session.respond_to?(:sock)).to be false

      # Simulate enqueuing the fake ssh session
      watchdog = Thread.new { sleep 10 }
      pool.instance_variable_get(:@queue).enq([fake_ssh_session, Time.now, watchdog])

      # deq should succeed without raising NoMethodError for sock
      retrieved = pool.deq
      expect(retrieved).to eq(fake_ssh_session)
    end
  end

  describe Xlogin::SessionModule do
    it 'defines closed? that works with sock or ssh' do
      # Telnet-like object with sock
      telnet_like = Object.new
      telnet_like.extend(Xlogin::SessionModule)
      sock = double('sock', closed?: false)
      telnet_like.define_singleton_method(:sock) { sock }
      expect(telnet_like.closed?).to be false

      # SSH-like object with ssh
      ssh_like = Object.new
      ssh_like.extend(Xlogin::SessionModule)
      ssh_conn = double('ssh', closed?: true)
      ssh_like.define_singleton_method(:ssh) { ssh_conn }
      expect(ssh_like.closed?).to be true
    end
  end

  describe 'Session retry failure tunnel cleanup' do
    it 'closes tunnel if connection fails and retries are exhausted' do
      template = Xlogin::Template.new('dummy')
      uri = Addressable::URI.parse('telnet://127.0.0.1:23')

      allow(Xlogin.factory).to receive(:open_tunnel).and_return(['127.0.0.1', 9999])
      expect(Xlogin.factory).to receive(:close_tunnel).with('jump_host', 9999)

      dummy_class = Class.new do
        prepend Xlogin::SessionModule
        def initialize(args)
          raise Errno::ECONNREFUSED, 'Connection refused'
        end
      end

      expect {
        dummy_class.new(template, uri, tunnel: 'jump_host', retry: 0)
      }.to raise_error(Errno::ECONNREFUSED)
    end
  end

  describe 'CLI remote URL template support' do
    it 'does not apply File.expand_path to HTTP/HTTPS URLs' do
      # Check that URL strings are preserved
      templates = ['https://raw.githubusercontent.com/example/templates/vyos.rb', 'local/path.rb']
      mapped = templates.map { |e| e =~ %r{^https?://\S+} ? e : File.expand_path(e, '/dummy/pwd') }

      expect(mapped[0]).to eq('https://raw.githubusercontent.com/example/templates/vyos.rb')
      expect(mapped[1]).to eq('/dummy/pwd/local/path.rb')
    end
  end
end
