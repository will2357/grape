require 'spec_helper'
require 'shared_versioning_examples'

describe Grape::API do
  subject { Class.new(Grape::API) }
  before { subject.default_format :txt }
  
  def app; subject end
  
  describe '.prefix' do
    it 'should route through with the prefix' do
      subject.prefix 'awesome/sauce'
      subject.get :hello do
        "Hello there."
      end
    
      get 'awesome/sauce/hello'
      last_response.body.should eql "Hello there."
      
      get '/hello'
      last_response.status.should eql 404
    end
  end

  describe '.version using path' do
    it_should_behave_like 'versioning' do
      let(:macro_options) do
        {
          :using => :path
        }
      end
    end
  end

  describe '.version using header' do
    it_should_behave_like 'versioning' do
      let(:macro_options) do
        {
          :using  => :header,
          :vendor => 'mycompany',
          :format => 'json'
        }
      end
    end

    # Behavior as defined by rfc2616 when no header is defined
    # http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
    describe 'no specified accept header' do
      # subject.version 'v1', :using => :header
      # subject.get '/hello' do
      #   'hello'
      # end

      # it 'should route' do
      #   get '/hello'
      #   last_response.status.should eql 200
      # end
    end

    it 'should route if any media type is allowed' do
      
    end
  end

  describe '.represent' do
    it 'should require a :with option' do
      expect{ subject.represent Object, {} }.to raise_error(ArgumentError)
    end

    it 'should add the association to the :representations setting' do
      klass = Class.new
      subject.represent Object, :with => klass
      subject.settings[:representations][Object].should == klass
    end
  end

  describe '.namespace' do
    it 'should be retrievable and converted to a path' do
      subject.namespace :awesome do
        namespace.should == '/awesome'
      end
    end
    
    it 'should come after the prefix and version' do
      subject.prefix :rad
      subject.version :v1, :using => :path
      
      subject.namespace :awesome do
        prepare_path('hello').should == '/rad/:version/awesome/hello(.:format)'
      end
    end
    
    it 'should cancel itself after the block is over' do
      subject.namespace :awesome do
        namespace.should == '/awesome'
      end
      
      subject.namespace.should == '/'
    end
    
    it 'should be stackable' do
      subject.namespace :awesome do
        namespace :rad do
          namespace.should == '/awesome/rad'
        end
        namespace.should == '/awesome'
      end
      subject.namespace.should == '/'
    end

    it 'should accept path segments correctly' do
      subject.namespace :members do
        namespace "/:member_id" do
          namespace.should == '/members/:member_id'
          get '/' do
            params[:member_id]
          end
        end
      end
      get '/members/23'
      last_response.body.should == "23"
    end
    
    it 'should be callable with nil just to push onto the stack' do
      subject.namespace do
        version 'v2', :using => :path
        prepare_path('hello').should == '/:version/hello(.:format)'
      end
      subject.send(:prepare_path, 'hello').should == '/hello(.:format)'
    end
    
    %w(group resource resources segment).each do |als|
      it "`.#{als}` should be an alias" do
        subject.send(als, :awesome) do
          namespace.should ==  "/awesome"
        end
      end
    end
  end
  
  describe '.route' do
    it 'should allow for no path' do
      subject.namespace :votes do
        get do
          "Votes"
        end
        
        post do
          "Created a Vote"
        end
      end
      
      get '/votes'
      last_response.body.should eql 'Votes'
      post '/votes'
      last_response.body.should eql 'Created a Vote'
    end
    
    it 'should allow for multiple paths' do
      subject.get(["/abc", "/def"]) do
        "foo"
      end
      
      get '/abc'
      last_response.body.should eql 'foo'
      get '/def'
      last_response.body.should eql 'foo'
    end

    it 'should allow for format' do
      subject.get("/abc") do
        "json"
      end
      
      get '/abc.json'
      last_response.body.should eql '"json"'
    end

    it 'should allow for format without corrupting a param' do
      subject.get('/:id') do
        params[:id]
      end

      get '/awesome.json'
      last_response.body.should eql "\"awesome\""
    end

    it 'should allow for format in namespace with no path' do
      subject.namespace :abc do
        get do
          "json"
        end
      end
      
      get '/abc.json'
      last_response.body.should eql '"json"'
    end
    
    it 'should allow for multiple verbs' do
      subject.route([:get, :post], '/abc') do
        "hiya"
      end
      
      get '/abc'
      last_response.body.should eql 'hiya'
      post '/abc'
      last_response.body.should eql 'hiya'
    end

    it 'should allow for multipart paths' do

      subject.route([:get, :post], '/:id/first') do
        "first"
      end
      
      subject.route([:get, :post], '/:id') do
        "ola"
      end
      subject.route([:get, :post], '/:id/first/second') do
        "second"
      end

      get '/1'
      last_response.body.should eql 'ola'
      post '/1'
      last_response.body.should eql 'ola'
      get '/1/first'
      last_response.body.should eql 'first'
      post '/1/first'
      last_response.body.should eql 'first'
      get '/1/first/second'
      last_response.body.should eql 'second'

    end
    
    it 'should allow for :any as a verb' do
      subject.route(:any, '/abc') do
        "lol"
      end
      
      %w(get post put delete).each do |m|
        send(m, '/abc')
        last_response.body.should eql 'lol'
      end
    end
    
    verbs = %w(post get head delete put)
    verbs.each do |verb|
      it "should allow and properly constrain a #{verb.upcase} method" do
        subject.send(verb, '/example') do
          verb
        end
        send(verb, '/example')
        last_response.body.should eql verb
        # Call it with a method other than the properly constrained one.
        send(verbs[(verbs.index(verb) + 1) % verbs.size], '/example')
        last_response.status.should eql 404
      end
    end
    
    it 'should return a 201 response code for POST by default' do
      subject.post('example') do
        "Created"
      end
      
      post '/example'
      last_response.status.should eql 201
      last_response.body.should eql 'Created'
    end
  end

  describe 'filters' do
    it 'should add a before filter' do
      subject.before { @foo = 'first'  }
      subject.before { @bar = 'second' }
      subject.get '/' do
        "#{@foo} #{@bar}"
      end

      get '/'
      last_response.body.should eql 'first second'
    end

    it 'should add a after filter' do
      m = double('after mock')
      subject.after { m.do_something! }
      subject.after { m.do_something! }
      subject.get '/' do
        @var ||= 'default'
      end

      m.should_receive(:do_something!).exactly(2).times
      get '/'
      last_response.body.should eql 'default'
    end
  end

  context 'format' do
    before do
      subject.get("/foo") { "bar" }
    end

    it 'should set content type for txt format' do
      get '/foo'
      last_response.headers['Content-Type'].should eql 'text/plain'
    end

    it 'should set content type for json' do
      get '/foo.json'
      last_response.headers['Content-Type'].should eql 'application/json'
    end

    it 'should set content type for error' do
      subject.get('/error') { error!('error in plain text', 500) }
      get '/error'
      last_response.headers['Content-Type'].should eql 'text/plain'
    end

    it 'should set content type for error' do
      subject.error_format :json
      subject.get('/error') { error!('error in json', 500) }
      get '/error.json'
      last_response.headers['Content-Type'].should eql 'application/json'
    end
  end
  
  context 'custom middleware' do
    class PhonyMiddleware
      def initialize(app, *args)
        @args = args
        @app = app
      end

      def call(env)
        env['phony.args'] ||= []
        env['phony.args'] << @args
        @app.call(env)
      end
    end

    describe '.middleware' do
      it 'should include middleware arguments from settings' do
        settings = Grape::Util::HashStack.new
        settings.stub!(:stack).and_return([{:middleware => [[PhonyMiddleware, 'abc', 123]]}])
        subject.stub!(:settings).and_return(settings)
        subject.middleware.should eql [[PhonyMiddleware, 'abc', 123]]
      end

      it 'should include all middleware from stacked settings' do
        settings = Grape::Util::HashStack.new
        settings.stub!(:stack).and_return [
          {:middleware => [[PhonyMiddleware, 123],[PhonyMiddleware, 'abc']]},
          {:middleware => [[PhonyMiddleware, 'foo']]}
        ]
        subject.stub!(:settings).and_return(settings)
  
        subject.middleware.should eql [
          [PhonyMiddleware, 123],
          [PhonyMiddleware, 'abc'],
          [PhonyMiddleware, 'foo']
        ]
      end
    end

    describe '.use' do
      it 'should add middleware' do
        subject.use PhonyMiddleware, 123
        subject.middleware.should eql [[PhonyMiddleware, 123]]
      end

      it 'should not show up outside the namespace' do
        subject.use PhonyMiddleware, 123
        subject.namespace :awesome do
          use PhonyMiddleware, 'abc'
          middleware.should == [[PhonyMiddleware, 123],[PhonyMiddleware, 'abc']]
        end

        subject.middleware.should eql [[PhonyMiddleware, 123]]        
      end

      it 'should actually call the middleware' do
        subject.use PhonyMiddleware, 'hello'
        subject.get '/' do
          env['phony.args'].first.first
        end

        get '/'
        last_response.body.should eql 'hello'
      end
    end
  end
  describe '.basic' do
    it 'should protect any resources on the same scope' do
      subject.http_basic do |u,p|
        u == 'allow'
      end
      subject.get(:hello){ "Hello, world."}
      get '/hello'
      last_response.status.should eql 401
      get '/hello', {}, 'HTTP_AUTHORIZATION' => encode_basic('allow','whatever')
      last_response.status.should eql 200
    end
    
    it 'should be scopable' do
      subject.get(:hello){ "Hello, world."}
      subject.namespace :admin do
        http_basic do |u,p|
          u == 'allow'
        end
        
        get(:hello){ "Hello, world." }
      end
      
      get '/hello'
      last_response.status.should eql 200
      get '/admin/hello'
      last_response.status.should eql 401
    end
    
    it 'should be callable via .auth as well' do
      subject.auth :http_basic do |u,p|
        u == 'allow'
      end
      
      subject.get(:hello){ "Hello, world."}
      get '/hello'
      last_response.status.should eql 401
      get '/hello', {}, 'HTTP_AUTHORIZATION' => encode_basic('allow','whatever')
      last_response.status.should eql 200
    end
  end
  
  describe '.helpers' do
    it 'should be accessible from the endpoint' do
      subject.helpers do
        def hello
          "Hello, world."
        end
      end
      
      subject.get '/howdy' do
        hello
      end
      
      get '/howdy'
      last_response.body.should eql 'Hello, world.'
    end
    
    it 'should be scopable' do
      subject.helpers do
        def generic
          'always there'
        end
      end
      
      subject.namespace :admin do
        helpers do
          def secret
            'only in admin'
          end
        end
        
        get '/secret' do
          [generic, secret].join ':'
        end
      end
      
      subject.get '/generic' do
        [generic, respond_to?(:secret)].join ':'
      end
      
      get '/generic'
      last_response.body.should eql 'always there:false'
      get '/admin/secret'
      last_response.body.should eql 'always there:only in admin'
    end
    
    it 'should be reopenable' do
      subject.helpers do
        def one
          1
        end
      end
      
      subject.helpers do
        def two
          2
        end
      end
      
      subject.get 'howdy' do
        [one, two]
      end
      
      lambda{get '/howdy'}.should_not raise_error
    end
  end
  
  describe '.scope' do
    # TODO: refactor this to not be tied to versioning. How about a generic
    # .setting macro?
    it 'should scope the various settings' do
      subject.prefix 'new'

      subject.scope :legacy do
        prefix 'legacy'
        get '/abc' do
          'abc'
        end
      end
      
      subject.get '/def' do
        'def'
      end
      
      get '/new/abc'
      last_response.status.should eql 404
      get '/legacy/abc'
      last_response.status.should eql 200
      get '/legacy/def'
      last_response.status.should eql 404
      get '/new/def'
      last_response.status.should eql 200
    end
  end
  
  describe ".rescue_from" do
    it 'should not rescue errors when rescue_from is not set' do
      subject.get '/exception' do
        raise "rain!"
      end    
      lambda { get '/exception' }.should raise_error
    end

    it 'should rescue all errors if rescue_from :all is called' do
      subject.rescue_from :all
      subject.get '/exception' do
        raise "rain!"
      end
      get '/exception'
      last_response.status.should eql 403
    end

    it 'should rescue only certain errors if rescue_from is called with specific errors' do
      subject.rescue_from ArgumentError
      subject.get('/rescued'){ raise ArgumentError }
      subject.get('/unrescued'){ raise "beefcake" }

      get '/rescued'
      last_response.status.should eql 403
      
      lambda{ get '/unrescued' }.should raise_error
    end
  end
  
  describe ".error_format" do
    it 'should rescue all errors and return :txt' do
      subject.rescue_from :all
      subject.error_format :txt
      subject.get '/exception' do
        raise "rain!"
      end    
      get '/exception'
      last_response.body.should eql "rain!"
    end

    it 'should rescue all errros and return :txt with backtrace' do
      subject.rescue_from :all, :backtrace => true
      subject.error_format :txt
      subject.get '/exception' do
        raise "rain!"
      end    
      get '/exception'
      last_response.body.start_with?("rain!\r\n").should be_true
    end

    it 'should rescue all errors and return :json' do
      subject.rescue_from :all
      subject.error_format :json
      subject.get '/exception' do
        raise "rain!"
      end    
      get '/exception'
      last_response.body.should eql '{"error":"rain!"}'
    end
    it 'should rescue all errors and return :json with backtrace' do
      subject.rescue_from :all, :backtrace => true
      subject.error_format :json
      subject.get '/exception' do
        raise "rain!"
      end    
      get '/exception'
      json = MultiJson.decode(last_response.body)
      json["error"].should eql 'rain!'
      json["backtrace"].length.should > 0
    end
    it 'should rescue error! and return txt' do
      subject.error_format :txt
      subject.get '/error' do
        error!("Access Denied", 401)
      end    
      get '/error'
      last_response.body.should eql "Access Denied"
    end
    it 'should rescue error! and return json' do
      subject.error_format :json
      subject.get '/error' do
        error!("Access Denied", 401)
      end    
      get '/error'
      last_response.body.should eql '{"error":"Access Denied"}'
    end
  end
  
  describe ".default_error_status" do
    it 'should allow setting default_error_status' do
      subject.rescue_from :all
      subject.default_error_status 200
      subject.get '/exception' do
        raise "rain!"
      end    
      get '/exception'
      last_response.status.should eql 200
    end
    it 'should have a default error status' do
      subject.rescue_from :all
      subject.get '/exception' do
        raise "rain!"
      end    
      get '/exception'
      last_response.status.should eql 403
    end
  end

  context "routes" do
    describe "empty api structure" do
      it "returns an empty array of routes" do
        subject.routes.should == []
      end
    end     
    describe "single method api structure" do
      before(:each) do
        subject.get :ping do 
          'pong'
        end
      end
      it "returns one route" do
        subject.routes.size.should == 1
        route = subject.routes[0]
        route.route_version.should be_nil
        route.route_path.should == "/ping(.:format)"
        route.route_method.should == "GET"
      end
    end    
    describe "api structure with two versions and a namespace" do
      class TwitterAPI < Grape::API
        # version v1
        version 'v1', :using => :path
        get "version" do 
          api.version
        end
        # version v2
        version 'v2', :using => :path
        prefix 'p'
        namespace "n1" do
          namespace "n2" do
            get "version" do
              api.version
            end
          end
        end
      end
      it "should return versions" do
        TwitterAPI::versions.should == [ 'v1', 'v2' ]
      end
      it "should set route paths" do
        TwitterAPI::routes.size.should >= 2
        TwitterAPI::routes[0].route_path.should == "/:version/version(.:format)"
        TwitterAPI::routes[1].route_path.should == "/p/:version/n1/n2/version(.:format)"
      end
      it "should set route versions" do
        TwitterAPI::routes[0].route_version.should == 'v1'
        TwitterAPI::routes[1].route_version.should == 'v2'
      end
      it "should set a nested namespace" do
        TwitterAPI::routes[1].route_namespace.should == "/n1/n2"
      end
      it "should set prefix" do
        TwitterAPI::routes[1].route_prefix.should == 'p'
      end
    end
    describe "api structure with additional parameters" do
      before(:each) do
        subject.get 'split/:string', { :params => [ "token" ], :optional_params => [ "limit" ] } do 
          params[:string].split(params[:token], (params[:limit] || 0).to_i)
        end
      end
      it "should split a string" do
        get "/split/a,b,c.json", :token => ','
        last_response.body.should == '["a","b","c"]'
      end
      it "should split a string with limit" do
        get "/split/a,b,c.json", :token => ',', :limit => '2'
        last_response.body.should == '["a","b,c"]'
      end
      it "should set route_params" do
        subject.routes.size.should == 1
        subject.routes[0].route_params.should == [ "string", "token" ]
        subject.routes[0].route_optional_params.should == [ "limit" ]
      end
    end
  end
  
  describe ".rescue_from klass, block" do
    it 'should rescue Exception' do
      subject.rescue_from RuntimeError do |e|
        rack_response("rescued from #{e.message}", 202)
      end
      subject.get '/exception' do
        raise "rain!"
      end
      get '/exception'
      last_response.status.should eql 202
      last_response.body.should == 'rescued from rain!'
    end
    it 'should rescue an error via rescue_from :all' do
      class ConnectionError < RuntimeError; end
      subject.rescue_from :all do |e|
        rack_response("rescued from #{e.class.name}", 500)
      end
      subject.get '/exception' do
        raise ConnectionError
      end
      get '/exception'
      last_response.status.should eql 500
      last_response.body.should == 'rescued from ConnectionError'
    end
    it 'should rescue a specific error' do
      class ConnectionError < RuntimeError; end
      subject.rescue_from ConnectionError do |e|
        rack_response("rescued from #{e.class.name}", 500)
      end
      subject.get '/exception' do
        raise ConnectionError
      end
      get '/exception'
      last_response.status.should eql 500
      last_response.body.should == 'rescued from ConnectionError'
    end
    it 'should rescue multiple specific errors' do
      class ConnectionError < RuntimeError; end
      class DatabaseError < RuntimeError; end
      subject.rescue_from ConnectionError do |e|
        rack_response("rescued from #{e.class.name}", 500)
      end
      subject.rescue_from DatabaseError do |e|
        rack_response("rescued from #{e.class.name}", 500)
      end
      subject.get '/connection' do
        raise ConnectionError
      end
      subject.get '/database' do
        raise DatabaseError
      end
      get '/connection'
      last_response.status.should eql 500
      last_response.body.should == 'rescued from ConnectionError'
      get '/database'
      last_response.status.should eql 500
      last_response.body.should == 'rescued from DatabaseError'
    end
    it 'should not rescue a different error' do
      class CommunicationError < RuntimeError; end
      subject.rescue_from RuntimeError do |e|
        rack_response("rescued from #{e.class.name}", 500)
      end
      subject.get '/uncaught' do
        raise CommunicationError
      end
      lambda { get '/uncaught' }.should raise_error(CommunicationError)
    end
  end

  describe '.mount.' do
    let(:mounted_app){ lambda{|env| [200, {}, ["MOUNTED"]]} }
  
    context 'with a bare rack app' do
      before do
        subject.mount mounted_app => '/mounty'
      end
    
      it 'should make a bare Rack app available at the endpoint' do
        get '/mounty'
        last_response.body.should == 'MOUNTED'
      end

      it 'should anchor the routes, passing all subroutes to it' do
        get '/mounty/awesome'
        last_response.body.should == 'MOUNTED'
      end

      it 'should be able to cascade' do
        subject.mount lambda{ |env| 
          headers = {}
          headers['X-Cascade'] == 'pass' unless env['PATH_INFO'].include?('boo')
          [200, headers, ["Farfegnugen"]]
        } => '/'

        get '/boo'
        last_response.body.should == 'Farfegnugen'
        get '/mounty'
        last_response.body.should == 'MOUNTED'
      end
    end

    context 'without a hash' do
      it 'should call through setting the route to "/"' do
        subject.mount mounted_app
        get '/'
        last_response.body.should == 'MOUNTED'
      end
    end
  end
end
