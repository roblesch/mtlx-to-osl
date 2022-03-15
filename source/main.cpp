
#include <iostream>
#include <string>

#include "MaterialXFormat/File.h"
#include "MaterialXFormat/XmlIo.h"
#include "MaterialXCore/Document.h"


namespace mx = MaterialX;


int main(int argc, char *argv[]) {

    if (argc != 3) {
        std::cerr << "usage: mtlx-to-osl [absolute-path-to-mtlx-file] [osl-outfile-name]" << std::endl;
        exit(EXIT_FAILURE);
    }

    mx::FilePath materialFilename(argv[1]);
    mx::FilePath oslFilename = argv[2];

    std::cout << '\n' << materialFilename.asString()
              << '\n' << oslFilename.asString()
              << '\n' << std::endl;

    // Load material document
    mx::DocumentPtr doc = mx::createDocument();
    mx::readFromXmlFile(doc, materialFilename);

    // Validate document
    std::string message;
    if (!doc->validate(&message))
    {
        std::cerr << "*** Validation warnings for " << materialFilename.getBaseName() << " ***" << std::endl;
        std::cerr << message;
    }

    std::cout << &doc;
}
