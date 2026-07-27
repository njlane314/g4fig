#include "G4Box.hh"
#include "G4Colour.hh"
#include "G4Cons.hh"
#include "G4Ellipsoid.hh"
#include "G4GDMLParser.hh"
#include "G4LogicalVolume.hh"
#include "G4Material.hh"
#include "G4ModelingParameters.hh"
#include "G4Orb.hh"
#include "G4Para.hh"
#include "G4PhysicalVolumeModel.hh"
#include "G4Polycone.hh"
#include "G4Polyhedra.hh"
#include "G4Polyhedron.hh"
#include "G4Sphere.hh"
#include "G4TessellatedSolid.hh"
#include "G4Torus.hh"
#include "G4Trap.hh"
#include "G4Trd.hh"
#include "G4Tubs.hh"
#include "G4VGraphicsScene.hh"
#include "G4VPhysicalVolume.hh"
#include "G4VSolid.hh"
#include "G4VisAttributes.hh"
#include "G4ios.hh"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#ifndef G4FIG_VERSION
#define G4FIG_VERSION "dev"
#endif

namespace {

constexpr std::size_t kDefaultMaxLines = 1'000'000;

struct Vec3 {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

struct Rule {
    std::regex pattern;
    std::string source;
    std::string value;
};

struct Options {
    std::string input;
    std::string output;
    std::string tracks;
    int width = 1200;
    int height = 675;
    int sides = 24;
    double fade = 0.07;
    double depthFade = 0.65;
    double lineWidth = 0.85;
    double padding = 0.055;
    double trackScale = 1.0;
    Vec3 view{1.0, 0.25, -0.12};
    Vec3 up{0.0, 1.0, 0.0};
    bool list = false;
    bool showWorld = false;
    bool auxiliaryEdges = false;
    int maxDepth = G4PhysicalVolumeModel::UNLIMITED;
    std::size_t maxLines = kDefaultMaxLines;
    std::vector<Rule> includes;
    std::vector<Rule> excludes;
    std::vector<Rule> styles;
    std::vector<Rule> labels;
};

struct Metadata {
    std::string path;
    std::string physical;
    std::string logical;
    std::string material;
    int depth = 0;

    std::string SearchText() const {
        return path + "\n" + physical + "\n" + logical + "\n" + material;
    }
};

struct Edge {
    Vec3 a;
    Vec3 b;
    Metadata metadata;
    std::string colour;
};

struct Track {
    Vec3 a;
    Vec3 b;
    std::string particle;
};

struct VolumeRow {
    Metadata metadata;
    std::string solid;
    std::size_t edges = 0;
};

struct ProjectedLine {
    double x1 = 0.0;
    double y1 = 0.0;
    double x2 = 0.0;
    double y2 = 0.0;
    double depth = 0.0;
    double opacity = 1.0;
    double width = 1.0;
    std::string colour;
    bool track = false;
    Metadata metadata;
};

struct LabelPosition {
    const Rule* rule = nullptr;
    double minX = std::numeric_limits<double>::infinity();
    double maxX = -std::numeric_limits<double>::infinity();
    double minY = std::numeric_limits<double>::infinity();
    double maxY = -std::numeric_limits<double>::infinity();
    double x = 0.0;
    double y = 0.0;
    std::size_t count = 0;
};

double Dot(const Vec3& a, const Vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

Vec3 Cross(const Vec3& a, const Vec3& b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}

Vec3 Normalized(const Vec3& v) {
    const double length = std::sqrt(Dot(v, v));
    if (length < 1.0e-12) {
        throw std::runtime_error("camera vectors must be non-zero");
    }
    return {v.x / length, v.y / length, v.z / length};
}

std::string XmlEscape(std::string_view text) {
    std::string escaped;
    escaped.reserve(text.size());
    for (const char c : text) {
        switch (c) {
        case '&':
            escaped += "&amp;";
            break;
        case '<':
            escaped += "&lt;";
            break;
        case '>':
            escaped += "&gt;";
            break;
        case '\"':
            escaped += "&quot;";
            break;
        case '\'':
            escaped += "&apos;";
            break;
        default:
            escaped += c;
            break;
        }
    }
    return escaped;
}

bool Matches(const std::regex& pattern, const Metadata& metadata) {
    return std::regex_search(metadata.SearchText(), pattern);
}

bool Selected(const Options& options, const Metadata& metadata) {
    if (!options.includes.empty()) {
        bool included = false;
        for (const auto& rule : options.includes) {
            included = included || Matches(rule.pattern, metadata);
        }
        if (!included)
            return false;
    }
    for (const auto& rule : options.excludes) {
        if (Matches(rule.pattern, metadata))
            return false;
    }
    return true;
}

std::string ColourFor(const Options& options, const Metadata& metadata) {
    for (auto it = options.styles.rbegin(); it != options.styles.rend(); ++it) {
        if (Matches(it->pattern, metadata))
            return it->value;
    }
    return "#ff5a1f";
}

std::string TrackColour(std::string_view particle) {
    if (particle == "proton")
        return "#2145f5";
    if (particle == "pi+")
        return "#21d94f";
    if (particle == "pi-")
        return "#ed4141";
    if (particle == "kaon+")
        return "#f39a25";
    if (particle == "kaon-")
        return "#8d37c8";
    if (particle == "kaon0L")
        return "#875523";
    if (particle == "mu+")
        return "#20b7d1";
    if (particle == "mu-")
        return "#e833a4";
    return "#24445f";
}

class StreamRedirect final {
  public:
    StreamRedirect(std::ostream& stream, std::ostream& destination)
        : stream_(stream), previous_(stream.rdbuf(destination.rdbuf())) {}

    ~StreamRedirect() {
        stream_.rdbuf(previous_);
    }

    StreamRedirect(const StreamRedirect&) = delete;
    StreamRedirect& operator=(const StreamRedirect&) = delete;

  private:
    std::ostream& stream_;
    std::streambuf* previous_;
};

class CaptureScene final : public G4VGraphicsScene {
  public:
    CaptureScene(G4PhysicalVolumeModel& model, const Options& options)
        : model_(model), options_(options) {}

    const std::vector<Edge>& Edges() const {
        return edges_;
    }
    const std::vector<VolumeRow>& Volumes() const {
        return volumes_;
    }

    void PreAddSolid(const G4Transform3D& transform, const G4VisAttributes&) override {
        transform_ = transform;
    }

    void PostAddSolid() override {}

    void AddSolid(const G4Box& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Cons& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Orb& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Para& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Sphere& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Torus& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Trap& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Trd& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Tubs& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Ellipsoid& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Polycone& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4Polyhedra& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4TessellatedSolid& solid) override {
        Capture(solid);
    }
    void AddSolid(const G4VSolid& solid) override {
        Capture(solid);
    }

    void AddCompound(const G4VTrajectory&) override {}
    void AddCompound(const G4VHit&) override {}
    void AddCompound(const G4VDigi&) override {}
    void AddCompound(const G4THitsMap<G4double>&) override {}
    void AddCompound(const G4THitsMap<G4StatDouble>&) override {}
    void AddCompound(const G4Mesh&) override {}

    void BeginPrimitives(const G4Transform3D& transform) override {
        transform_ = transform;
    }
    void EndPrimitives() override {}
    void BeginPrimitives2D(const G4Transform3D& transform) override {
        transform_ = transform;
    }
    void EndPrimitives2D() override {}

    void AddPrimitive(const G4Polyline&) override {}
    void AddPrimitive(const G4Text&) override {}
    void AddPrimitive(const G4Circle&) override {}
    void AddPrimitive(const G4Square&) override {}
    void AddPrimitive(const G4Polymarker&) override {}
    void AddPrimitive(const G4Polyhedron& polyhedron) override {
        CapturePolyhedron(polyhedron, "polyhedron");
    }
    void AddPrimitive(const G4Plotter&) override {}

  private:
    Metadata CurrentMetadata() const {
        Metadata metadata;
        metadata.depth = model_.GetCurrentDepth();
        if (const auto* pv = model_.GetCurrentPV()) {
            metadata.physical = pv->GetName();
        }
        if (const auto* lv = model_.GetCurrentLV()) {
            metadata.logical = lv->GetName();
        }
        if (const auto* material = model_.GetCurrentMaterial()) {
            metadata.material = material->GetName();
        }

        for (const auto& node : model_.GetFullPVPath()) {
            const auto* pv = node.GetPhysicalVolume();
            if (!pv)
                continue;
            metadata.path +=
                "/" + std::string(pv->GetName()) + "[" + std::to_string(node.GetCopyNo()) + "]";
        }
        if (metadata.path.empty())
            metadata.path = "/";
        return metadata;
    }

    template <typename Solid> void Capture(const Solid& solid) {
        const G4Polyhedron* polyhedron = solid.GetPolyhedron();
        const std::size_t edgeCount =
            polyhedron ? static_cast<std::size_t>(polyhedron->GetNoFacets()) : 0;
        const Metadata metadata = CurrentMetadata();

        if (!Selected(options_, metadata))
            return;
        if (options_.list) {
            volumes_.push_back({metadata, solid.GetEntityType(), edgeCount});
            return;
        }
        if (metadata.depth == 0 && !options_.showWorld)
            return;
        if (!polyhedron)
            return;
        CapturePolyhedron(*polyhedron, solid.GetEntityType());
    }

    void CapturePolyhedron(const G4Polyhedron& polyhedron, const std::string& solidType) {
        const Metadata metadata = CurrentMetadata();
        if (!Selected(options_, metadata))
            return;

        if (options_.list) {
            volumes_.push_back(
                {metadata, solidType, static_cast<std::size_t>(polyhedron.GetNoFacets())});
            return;
        }
        if (metadata.depth == 0 && !options_.showWorld)
            return;
        if (polyhedron.GetNoVertices() == 0 || polyhedron.GetNoFacets() == 0)
            return;

        const std::string colour = ColourFor(options_, metadata);
        G4Point3D a;
        G4Point3D b;
        G4int visible = 0;
        G4bool more = false;
        do {
            more = polyhedron.GetNextEdge(a, b, visible);
            if (!visible && !options_.auxiliaryEdges)
                continue;

            const auto worldA = transform_ * a;
            const auto worldB = transform_ * b;
            edges_.push_back({{worldA.x(), worldA.y(), worldA.z()},
                              {worldB.x(), worldB.y(), worldB.z()},
                              metadata,
                              colour});
            if (edges_.size() > options_.maxLines) {
                throw std::runtime_error(
                    "geometry exceeds --max-lines; filter volumes or raise the limit");
            }
        } while (more);
    }

    G4PhysicalVolumeModel& model_;
    const Options& options_;
    G4Transform3D transform_;
    std::vector<Edge> edges_;
    std::vector<VolumeRow> volumes_;
};

std::vector<Track> ReadTracks(const std::string& path, double scale) {
    if (path.empty())
        return {};
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("cannot open track file: " + path);

    std::vector<Track> tracks;
    std::string line;
    std::size_t lineNumber = 0;
    while (std::getline(input, line)) {
        ++lineNumber;
        const auto first = line.find_first_not_of(" \t\r");
        if (first == std::string::npos || line[first] == '#')
            continue;
        if (const auto comment = line.find('#'); comment != std::string::npos) {
            line.erase(comment);
        }

        std::istringstream row(line);
        Track track;
        if (!(row >> track.a.x >> track.a.y >> track.a.z >> track.b.x >> track.b.y >> track.b.z)) {
            throw std::runtime_error("invalid track row " + std::to_string(lineNumber));
        }
        row >> track.particle;
        if (track.particle.empty())
            track.particle = "track";
        track.a.x *= scale;
        track.a.y *= scale;
        track.a.z *= scale;
        track.b.x *= scale;
        track.b.y *= scale;
        track.b.z *= scale;
        tracks.push_back(std::move(track));
    }
    return tracks;
}

Vec3 ParseVector(const std::string& text, std::string_view option) {
    std::string copy = text;
    std::replace(copy.begin(), copy.end(), ',', ' ');
    std::istringstream input(copy);
    Vec3 value;
    if (!(input >> value.x >> value.y >> value.z)) {
        throw std::runtime_error(std::string(option) + " expects X,Y,Z");
    }
    std::string extra;
    if (input >> extra) {
        throw std::runtime_error(std::string(option) + " expects exactly X,Y,Z");
    }
    return value;
}

std::pair<int, int> ParseSize(const std::string& text) {
    const auto separator = text.find_first_of("xX");
    if (separator == std::string::npos) {
        throw std::runtime_error("--size expects WIDTHxHEIGHT");
    }
    const int width = std::stoi(text.substr(0, separator));
    const int height = std::stoi(text.substr(separator + 1));
    if (width < 64 || height < 64) {
        throw std::runtime_error("--size dimensions must be at least 64 pixels");
    }
    return {width, height};
}

Rule PatternRule(const std::string& source, std::string value = {}) {
    return {std::regex(source, std::regex::extended), source, std::move(value)};
}

Rule AssignmentRule(const std::string& text, std::string_view option) {
    const auto separator = text.find('=');
    if (separator == std::string::npos || separator == 0 || separator + 1 == text.size()) {
        throw std::runtime_error(std::string(option) + " expects REGEX=VALUE");
    }
    return PatternRule(text.substr(0, separator), text.substr(separator + 1));
}

double ParseRange(const std::string& text, std::string_view option, double low, double high) {
    const double value = std::stod(text);
    if (!std::isfinite(value) || value < low || value > high) {
        std::ostringstream message;
        message << option << " must be between " << low << " and " << high;
        throw std::runtime_error(message.str());
    }
    return value;
}

void PrintHelp(std::ostream& output) {
    output << "usage: g4fig [options] FILE.gdml\n"
              "\n"
              "Render Geant4 GDML as a publication-style SVG wireframe.\n"
              "SVG is written to stdout and diagnostics to stderr.\n"
              "\n"
              "  -o FILE                  write SVG (container: SVG, PNG, or PDF)\n"
              "  --list                   list placed volumes as TSV\n"
              "  --size WIDTHxHEIGHT      canvas size (1200x675)\n"
              "  --view X,Y,Z             direction from scene to camera\n"
              "  --up X,Y,Z               approximate screen-up direction\n"
              "  --include REGEX          keep matching geometry\n"
              "  --exclude REGEX          omit matching geometry\n"
              "  --style REGEX=COLOUR     style matching geometry; repeatable\n"
              "  --label REGEX=TEXT       add a haloed label; repeatable\n"
              "  --tracks FILE            overlay track segment rows\n"
              "  --track-scale NUMBER     scale track coordinates (1)\n"
              "  --fade FRACTION          edge fade width (0.07)\n"
              "  --depth-fade STRENGTH    distant-line fade (0.65)\n"
              "  --line-width NUMBER      geometry line width (0.85)\n"
              "  --padding FRACTION       fitted geometry margin (0.055)\n"
              "  --sides NUMBER           curved-solid tessellation (24)\n"
              "  --max-depth NUMBER       stop traversal at hierarchy depth\n"
              "  --max-lines NUMBER       safety limit (1000000)\n"
              "  --show-world             include the world solid\n"
              "  --aux-edges              include hidden mesh edges\n"
              "  -h, --help               show this help\n"
              "  --version                show the version\n";
}

Options ParseArguments(int argc, char** argv) {
    Options options;

    auto next = [&](int& index, std::string_view option) -> std::string {
        if (++index >= argc) {
            throw std::runtime_error(std::string(option) + " requires an argument");
        }
        return argv[index];
    };

    for (int i = 1; i < argc; ++i) {
        const std::string argument = argv[i];
        if (argument == "-h" || argument == "--help") {
            PrintHelp(std::cout);
            std::exit(0);
        } else if (argument == "--version") {
            std::cout << "g4fig " << G4FIG_VERSION << '\n';
            std::exit(0);
        } else if (argument == "-o") {
            options.output = next(i, argument);
        } else if (argument == "--list") {
            options.list = true;
        } else if (argument == "--size") {
            const auto [width, height] = ParseSize(next(i, argument));
            options.width = width;
            options.height = height;
        } else if (argument == "--view") {
            options.view = ParseVector(next(i, argument), argument);
        } else if (argument == "--up") {
            options.up = ParseVector(next(i, argument), argument);
        } else if (argument == "--include") {
            const std::string pattern = next(i, argument);
            options.includes.push_back(PatternRule(pattern));
        } else if (argument == "--exclude") {
            const std::string pattern = next(i, argument);
            options.excludes.push_back(PatternRule(pattern));
        } else if (argument == "--style") {
            options.styles.push_back(AssignmentRule(next(i, argument), argument));
        } else if (argument == "--label") {
            options.labels.push_back(AssignmentRule(next(i, argument), argument));
        } else if (argument == "--tracks") {
            options.tracks = next(i, argument);
        } else if (argument == "--track-scale") {
            options.trackScale = ParseRange(next(i, argument), argument, 1.0e-12, 1.0e12);
        } else if (argument == "--fade") {
            options.fade = ParseRange(next(i, argument), argument, 0.0, 0.45);
        } else if (argument == "--depth-fade") {
            options.depthFade = ParseRange(next(i, argument), argument, 0.0, 1.0);
        } else if (argument == "--line-width") {
            options.lineWidth = ParseRange(next(i, argument), argument, 0.05, 20.0);
        } else if (argument == "--padding") {
            options.padding = ParseRange(next(i, argument), argument, 0.0, 0.45);
        } else if (argument == "--sides") {
            options.sides = std::stoi(next(i, argument));
            if (options.sides < 8 || options.sides > 360) {
                throw std::runtime_error("--sides must be between 8 and 360");
            }
        } else if (argument == "--max-depth") {
            const long long value = std::stoll(next(i, argument));
            if (value < 0 || value > std::numeric_limits<int>::max())
                throw std::runtime_error("--max-depth must be a non-negative integer");
            options.maxDepth = static_cast<int>(value);
        } else if (argument == "--max-lines") {
            const long long value = std::stoll(next(i, argument));
            if (value < 1)
                throw std::runtime_error("--max-lines must be positive");
            options.maxLines = static_cast<std::size_t>(value);
        } else if (argument == "--show-world") {
            options.showWorld = true;
        } else if (argument == "--aux-edges") {
            options.auxiliaryEdges = true;
        } else if (!argument.empty() && argument.front() == '-') {
            throw std::runtime_error("unknown option: " + argument);
        } else if (options.input.empty()) {
            options.input = argument;
        } else {
            throw std::runtime_error("only one GDML input may be specified");
        }
    }

    if (options.input.empty())
        throw std::runtime_error("no GDML input specified");
    return options;
}

std::vector<ProjectedLine> Project(const std::vector<Edge>& edges, const std::vector<Track>& tracks,
                                   const Options& options, std::vector<LabelPosition>& labels) {
    const Vec3 forward = Normalized(options.view);
    const Vec3 right = Normalized(Cross(forward, Normalized(options.up)));
    const Vec3 screenUp = Normalized(Cross(right, forward));

    std::vector<ProjectedLine> lines;
    lines.reserve(edges.size() + tracks.size());
    double minX = std::numeric_limits<double>::infinity();
    double maxX = -std::numeric_limits<double>::infinity();
    double minY = std::numeric_limits<double>::infinity();
    double maxY = -std::numeric_limits<double>::infinity();
    double minDepth = std::numeric_limits<double>::infinity();
    double maxDepth = -std::numeric_limits<double>::infinity();

    auto addBounds = [&](double x, double y) {
        minX = std::min(minX, x);
        maxX = std::max(maxX, x);
        minY = std::min(minY, y);
        maxY = std::max(maxY, y);
    };

    for (const auto& edge : edges) {
        ProjectedLine line;
        line.x1 = Dot(edge.a, right);
        line.y1 = Dot(edge.a, screenUp);
        line.x2 = Dot(edge.b, right);
        line.y2 = Dot(edge.b, screenUp);
        line.depth = 0.5 * (Dot(edge.a, forward) + Dot(edge.b, forward));
        line.width = options.lineWidth;
        line.colour = edge.colour;
        line.metadata = edge.metadata;
        addBounds(line.x1, line.y1);
        addBounds(line.x2, line.y2);
        minDepth = std::min(minDepth, line.depth);
        maxDepth = std::max(maxDepth, line.depth);
        lines.push_back(std::move(line));
    }

    for (const auto& track : tracks) {
        ProjectedLine line;
        line.x1 = Dot(track.a, right);
        line.y1 = Dot(track.a, screenUp);
        line.x2 = Dot(track.b, right);
        line.y2 = Dot(track.b, screenUp);
        line.depth = std::numeric_limits<double>::infinity();
        line.opacity = 0.86;
        line.width = std::max(1.4, options.lineWidth * 1.9);
        line.colour = TrackColour(track.particle);
        line.track = true;
        addBounds(line.x1, line.y1);
        addBounds(line.x2, line.y2);
        lines.push_back(std::move(line));
    }

    if (lines.empty())
        throw std::runtime_error("no selected geometry or tracks to render");

    const double spanX = std::max(1.0e-12, maxX - minX);
    const double spanY = std::max(1.0e-12, maxY - minY);
    const double innerWidth = options.width * (1.0 - 2.0 * options.padding);
    const double innerHeight = options.height * (1.0 - 2.0 * options.padding);
    const double scale = std::min(innerWidth / spanX, innerHeight / spanY);
    const double offsetX = 0.5 * (options.width - spanX * scale) - minX * scale;
    const double offsetY = 0.5 * (options.height + spanY * scale) + minY * scale;
    const double depthSpan = std::max(1.0e-12, maxDepth - minDepth);

    labels.reserve(options.labels.size());
    for (const auto& label : options.labels)
        labels.push_back({&label});

    for (auto& line : lines) {
        if (!line.track) {
            const double nearness = (line.depth - minDepth) / depthSpan;
            line.opacity = 0.74 * (1.0 - options.depthFade * (0.82 * (1.0 - nearness)));
            for (auto& label : labels) {
                if (Matches(label.rule->pattern, line.metadata)) {
                    label.minX = std::min({label.minX, line.x1, line.x2});
                    label.maxX = std::max({label.maxX, line.x1, line.x2});
                    label.minY = std::min({label.minY, line.y1, line.y2});
                    label.maxY = std::max({label.maxY, line.y1, line.y2});
                    ++label.count;
                }
            }
        }
        line.x1 = offsetX + line.x1 * scale;
        line.y1 = offsetY - line.y1 * scale;
        line.x2 = offsetX + line.x2 * scale;
        line.y2 = offsetY - line.y2 * scale;
    }

    for (auto& label : labels) {
        if (label.count == 0)
            continue;
        label.x = offsetX + 0.5 * (label.minX + label.maxX) * scale;
        label.y = offsetY - 0.5 * (label.minY + label.maxY) * scale;
    }

    std::stable_sort(lines.begin(), lines.end(), [](const auto& a, const auto& b) {
        if (a.track != b.track)
            return !a.track;
        return a.depth < b.depth;
    });
    return lines;
}

void WriteSvg(std::ostream& output, const std::vector<Edge>& edges,
              const std::vector<Track>& tracks, const Options& options) {
    std::vector<LabelPosition> labels;
    const auto lines = Project(edges, tracks, options, labels);
    const double fadePercent = options.fade * 100.0;

    output << std::fixed << std::setprecision(2);
    output << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" << options.width
           << "\" height=\"" << options.height << "\" viewBox=\"0 0 " << options.width << ' '
           << options.height << "\" role=\"img\" aria-label=\"GDML geometry wireframe\">\n";
    output << "<defs>\n"
           << "  <linearGradient id=\"fade-x\"><stop offset=\"0%\" stop-color=\"black\"/>"
           << "<stop offset=\"" << fadePercent << "%\" stop-color=\"white\"/>"
           << "<stop offset=\"" << 100.0 - fadePercent << "%\" stop-color=\"white\"/>"
           << "<stop offset=\"100%\" stop-color=\"black\"/></linearGradient>\n"
           << "  <linearGradient id=\"fade-y\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
           << "<stop offset=\"0%\" stop-color=\"black\"/>"
           << "<stop offset=\"" << fadePercent << "%\" stop-color=\"white\"/>"
           << "<stop offset=\"" << 100.0 - fadePercent << "%\" stop-color=\"white\"/>"
           << "<stop offset=\"100%\" stop-color=\"black\"/></linearGradient>\n"
           << "  <mask id=\"mask-x\"><rect width=\"100%\" height=\"100%\" "
              "fill=\"url(#fade-x)\"/></mask>\n"
           << "  <mask id=\"mask-y\"><rect width=\"100%\" height=\"100%\" "
              "fill=\"url(#fade-y)\"/></mask>\n"
           << "  <filter id=\"paper-halo\" x=\"-40%\" y=\"-100%\" width=\"180%\" height=\"300%\">"
           << "<feGaussianBlur stdDeviation=\"5.5\"/></filter>\n"
           << "</defs>\n"
           << "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n";

    if (options.fade > 0.0) {
        output << "<g mask=\"url(#mask-x)\"><g mask=\"url(#mask-y)\">\n";
    } else {
        output << "<g>\n";
    }

    for (const auto& line : lines) {
        output << "<line x1=\"" << line.x1 << "\" y1=\"" << line.y1 << "\" x2=\"" << line.x2
               << "\" y2=\"" << line.y2 << "\" stroke=\"" << XmlEscape(line.colour)
               << "\" stroke-opacity=\"" << line.opacity << "\" stroke-width=\"" << line.width
               << "\" stroke-linecap=\"round\" vector-effect=\"non-scaling-stroke\"/>\n";
    }
    output << (options.fade > 0.0 ? "</g></g>\n" : "</g>\n");

    for (const auto& label : labels) {
        if (label.count == 0) {
            std::cerr << "g4fig: label pattern matched no rendered geometry: "
                      << label.rule->source << '\n';
            continue;
        }
        const double textWidth = std::max(34.0, 8.2 * label.rule->value.size());
        output << "<g>\n"
               << "  <rect x=\"" << label.x - 0.5 * textWidth - 8.0 << "\" y=\"" << label.y - 18.0
               << "\" width=\"" << textWidth + 16.0 << "\" height=\"28\" rx=\"10\" fill=\"white\""
               << " fill-opacity=\"0.96\" filter=\"url(#paper-halo)\"/>\n"
               << "  <text x=\"" << label.x << "\" y=\"" << label.y
               << "\" text-anchor=\"middle\" dominant-baseline=\"middle\""
               << " font-family=\"Helvetica,Arial,sans-serif\" font-size=\"16\""
               << " fill=\"#1f2933\">" << XmlEscape(label.rule->value) << "</text>\n"
               << "</g>\n";
    }
    output << "</svg>\n";
}

void WriteList(std::ostream& output, const std::vector<VolumeRow>& volumes) {
    output << "path\tphysical\tlogical\tmaterial\tdepth\tsolid\tfacets\n";
    for (const auto& volume : volumes) {
        output << volume.metadata.path << '\t' << volume.metadata.physical << '\t'
               << volume.metadata.logical << '\t' << volume.metadata.material << '\t'
               << volume.metadata.depth << '\t' << volume.solid << '\t' << volume.edges << '\n';
    }
}

} // namespace

int main(int argc, char** argv) {
    try {
        const Options options = ParseArguments(argc, argv);

        StreamRedirect redirectG4cout(G4cout, std::cerr);
        StreamRedirect redirectG4debug(G4debug, std::cerr);
        G4Polyhedron::SetNumberOfRotationSteps(options.sides);

        G4GDMLParser parser;
        parser.Read(options.input, false);
        G4VPhysicalVolume* world = parser.GetWorldVolume();
        if (!world)
            throw std::runtime_error("GDML contains no world volume");

        G4ModelingParameters parameters;
        G4PhysicalVolumeModel model(world, options.maxDepth, G4Transform3D(), &parameters);
        CaptureScene scene(model, options);
        model.DescribeYourselfTo(scene);

        std::unique_ptr<std::ofstream> file;
        std::ostream* output = &std::cout;
        if (!options.output.empty()) {
            file = std::make_unique<std::ofstream>(options.output);
            if (!*file)
                throw std::runtime_error("cannot open output: " + options.output);
            output = file.get();
        }

        if (options.list) {
            WriteList(*output, scene.Volumes());
        } else {
            const auto tracks = ReadTracks(options.tracks, options.trackScale);
            WriteSvg(*output, scene.Edges(), tracks, options);
        }

        G4Polyhedron::ResetNumberOfRotationSteps();
        return 0;
    } catch (const std::regex_error& error) {
        std::cerr << "g4fig: invalid regular expression: " << error.what() << '\n';
    } catch (const std::exception& error) {
        std::cerr << "g4fig: " << error.what() << '\n';
    }
    return 1;
}
