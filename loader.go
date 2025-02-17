package modgearman

import (
	"io/ioutil"
	"log"
	"os"
	"path"
)

//returns the secret_key as byte array from the location in the worker.cfg
func getKey(config *configurationStruct) []byte {
	if config.encryption {
		if config.key != "" {
			return fixKeySize([]byte(config.key))
		}
		if config.keyfile != "" {
			return fixKeySize(readKeyFile(config.keyfile))
		}
		logger.Panic("no key set but encyption enabled!")
		return nil
	}
	return nil

}

//loads the keyfile and extracts the key, if a newline is at the end it gets cut off
func readKeyFile(path string) []byte {
	dat, err := ioutil.ReadFile(path)
	if err != nil {
		log.Panic("could not open keyfile")
	}
	if len(dat) > 1 && dat[len(dat)-1] == 10 {
		return dat[:len(dat)-1]
	}

	return dat

}

func fixKeySize(key []byte) []byte {
	if len(key) > 32 {
		return key[0:32]
	}
	for {
		if len(key) == 32 {
			return key
		}
		key = append(key, 0)
	}
}

func openFileOrCreate(path string) (os.File, error) {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		createDirectoryAndFile(path)
		//open the file
		file, err := os.Open(path)
		if err != nil {
			logger.Errorf("could not open file %s: %s", path, err.Error())
			return *file, err
		}
		return *file, nil
	}
	//open the file
	file, err := os.Open(path)
	if err != nil {
		logger.Errorf("could not open file %s: %s", path, err.Error())
	}
	return *file, nil

}

func createDirectoryAndFile(pathe string) {
	directory, file := path.Split(pathe)
	if directory != "" {
		err := os.MkdirAll(directory, 0755)
		if err != nil {
			logger.Panic(err)
		}
		_, err = os.Create(directory + "/" + file)
		if err != nil {
			logger.Panic(err)
		}
	} else {
		_, err := os.Create(file)
		if err != nil {
			logger.Panic(err)
		}
	}

}
