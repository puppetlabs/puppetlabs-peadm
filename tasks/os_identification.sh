if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        osfamily="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
        osfamily="macOS"
elif [[ "$OSTYPE" == "cygwin" ]]; then
         osfamily="cygwin"
elif [[ "$OSTYPE" == "msys" ]]; then
          osfamily="msys"
elif [[ "$OSTYPE" == "win32" ]]; then
       osfamily="windows"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
         osfamily="freebsd"
else
        osfamily="unknown"
fi

  echo  $osfamily
