

desc "Setup Opus library"
task :setup do
	if(!File.exists?("opus-1.1"))
		puts("\nDownloading Opus source...")
		sh("curl -O http://downloads.xiph.org/releases/opus/opus-1.1.tar.gz")
		sh("tar -xzf opus-1.1.tar.gz")
		sh("rm source") if File.exists?("source")
		sh("ln -s opus-1.1 source")
	end

	puts("\nReady to go")
end