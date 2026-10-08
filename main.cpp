#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QRegularExpression>
#include <QTextStream>
#include <QUrl>
#include <QVariantMap>

class ThemeProvider : public QObject
{
    Q_OBJECT

public:
    Q_INVOKABLE QVariantMap colors() const
    {
        QVariantMap result {
            {QStringLiteral("background"), QStringLiteral("#121212")},
            {QStringLiteral("foreground"), QStringLiteral("#bebebe")},
            {QStringLiteral("accent"), QStringLiteral("#e68e0d")},
            {QStringLiteral("selection"), QStringLiteral("#2a2a2a")},
            {QStringLiteral("muted"), QStringLiteral("#555555")}
        };

        QString colorsPath = qEnvironmentVariable("HOME")
            + QStringLiteral("/.local/state/omarchy/current/theme/colors.toml");
        if (!QFile::exists(colorsPath)) {
            QProcess omarchy;
            omarchy.start(QStringLiteral("omarchy"), {QStringLiteral("theme"), QStringLiteral("current")});
            if (omarchy.waitForFinished(1000) && omarchy.exitStatus() == QProcess::NormalExit && omarchy.exitCode() == 0) {
                const QString theme = QString::fromLocal8Bit(omarchy.readAllStandardOutput()).trimmed()
                    .toLower().replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("-"));
                if (!theme.isEmpty())
                    colorsPath = QStringLiteral("/usr/share/omarchy/themes/") + theme + QStringLiteral("/colors.toml");
            }
        }

        QFile colorsFile(colorsPath);
        if (!colorsFile.open(QIODevice::ReadOnly | QIODevice::Text))
            return result;

        const QRegularExpression linePattern(
            QStringLiteral("^\\s*(background|foreground|accent|selection|muted)\\s*=\\s*[\\\"']?(#[0-9A-Fa-f]{6})"));
        QTextStream stream(&colorsFile);
        while (!stream.atEnd()) {
            const QRegularExpressionMatch match = linePattern.match(stream.readLine());
            if (match.hasMatch())
                result[match.captured(1)] = match.captured(2);
        }
        return result;
    }
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("OmaPaint"));
    app.setApplicationDisplayName(QStringLiteral("OmaPaint"));
    app.setOrganizationName(QStringLiteral("Omarchy"));

    ThemeProvider themeProvider;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("themeProvider"), &themeProvider);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/OmaPaint/quickpaint.qml")));

    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}

#include "main.moc"
