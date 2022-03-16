#include "MaterialXCore/Document.h"
#include "MaterialXFormat/File.h"
#include "MaterialXFormat/Util.h"
#include "MaterialXFormat/XmlIo.h"
#include "MaterialXGenOsl/OslShaderGenerator.h"
#include "MaterialXRender/ShaderRenderer.h"
#include "MaterialXRender/Util.h"
#include "MaterialXGenShader/GenContext.h"
#include "MaterialXGenShader/Util.h"

#include <iostream>
#include <string>
#include <fstream>


namespace mx = MaterialX;


mx::DocumentPtr LoadStdLib(const mx::FileSearchPath &searchPath) {
    /*
     * Load MaterialX data libraries from MaterialX/libraries.
     * searchPath is the absolute path to MaterialX root.
     */
    mx::DocumentPtr stdLib;
    mx::FilePathVec libraryFolders = {"libraries"};
    mx::StringSet xincludeFiles;

    try {
        stdLib = mx::createDocument();
        xincludeFiles = mx::loadLibraries(libraryFolders, searchPath, stdLib);
        if (xincludeFiles.empty()) {
            std::cerr << "Could not find standard data libraries on the given search path: " << searchPath.asString()
                      << std::endl;
        }
    } catch (std::exception &e) {
        std::cerr << "Failed to load standard data libraries: " << e.what() << std::endl;
        exit(EXIT_FAILURE);
    }

    return stdLib;
}

mx::GenContext InitGenContext(const mx::FileSearchPath &searchPath) {
    /*
     * Init shadergen context.
     * searchPath is absolute path to MaterialX root.
     */
    mx::GenContext context = mx::GenContext(mx::OslShaderGenerator::create());

    for (const mx::FilePath &path: searchPath) {
        context.registerSourceCodeSearchPath(path / "libraries");
    }

    return context;
}

void WriteOslShaderFromDoc(const mx::FilePath &materialFilename, const mx::FilePath &oslFilename,
                           const mx::FileSearchPath &searchPath, mx::GenContext context,
                           const mx::DocumentPtr &stdLib) {
    /*
     * Write an OSL shader from a *.mtlx document.
     * materialFilename is absolute path to *.mtlx document.
     * oslFilename is the output file.
     * searchPath is absolute path to MaterialX root.
     * context is a configured shadergen context.
     * stdLib is a document ptr to MaterialX data libraries.
     */
    mx::XmlReadOptions readOptions;

    try {
        // Load material document
        mx::DocumentPtr doc = mx::createDocument();
        mx::readFromXmlFile(doc, materialFilename, searchPath, &readOptions);

        // Import libraries
        doc->importLibrary(stdLib);

        // Validate the document
        std::string message;
        if (!doc->validate(&message)) {
            std::cerr << "*** Validation warnings for " << materialFilename.getBaseName() << " ***" << std::endl;
            std::cerr << message;
        }

        // Find renderable elements
        std::vector<mx::TypedElementPtr> docElems;
        mx::findRenderableElements(doc, docElems);
        if (docElems.empty()) {
            throw mx::Exception("No renderable elements found in " + materialFilename.getBaseName());
        }
        auto docElem = docElems.front();
        mx::TypedElementPtr renderableElem = docElem;
        mx::NodePtr node = docElem->asA<mx::Node>();
        if (node && node->getType() == mx::MATERIAL_TYPE_STRING) {
            std::vector<mx::NodePtr> shaderNodes = getShaderNodes(node);
            if (!shaderNodes.empty()) {
                renderableElem = shaderNodes[0];
            }
        }
        auto renderablePath = renderableElem->getNamePath();
        mx::ElementPtr elemptr = doc->getDescendant(renderablePath);
        mx::TypedElementPtr typedElem = elemptr ? elemptr->asA<mx::TypedElement>() : nullptr;

        // Create shader
        const bool hasTransparency = mx::isTransparentSurface(typedElem, context.getShaderGenerator().getTarget());
        mx::GenContext materialContext = context;
        materialContext.getOptions().hwTransparency = hasTransparency;
        mx::ShaderPtr shader = createShader(typedElem->getNamePath(), materialContext, typedElem);

        // Write shader
        const std::string &pixelShader = shader->getSourceCode(mx::Stage::PIXEL);
        std::ofstream file;
        file.open(oslFilename);
        file << pixelShader;
        file.close();
    } catch (mx::ExceptionRenderError &e) {
        for (const std::string &error: e.errorLog()) {
            std::cerr << error << std::endl;
            exit(EXIT_FAILURE);
        }
    } catch (std::exception &e) {
        std::cerr << "Failed to load material: " << e.what() << std::endl;
        exit(EXIT_FAILURE);
    }
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        std::cerr << "usage: mtlx-to-osl [absolute-path-to-mtlx-file] [absolute-path-to-mtlx-libs] [osl-outfile-name]"
                  << std::endl;
        exit(EXIT_FAILURE);
    }

    mx::FilePath materialFilename(argv[1]);
    mx::FileSearchPath searchPath(argv[2]);
    mx::FilePath oslFilename = argv[3];

    std::cout << '\n' << materialFilename.asString() << '\n' << oslFilename.asString() << std::endl;

    // Load standard libraries
    mx::DocumentPtr stdLib = LoadStdLib(searchPath);

    // Initialize generator context
    mx::GenContext context = InitGenContext(searchPath);

    // Write shader file
    WriteOslShaderFromDoc(materialFilename, oslFilename, searchPath, context, stdLib);
}
